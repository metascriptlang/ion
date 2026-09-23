// Ion Windows — window lifecycle: ionOpen, ionClose, ionResourcePath.
//
// Phase 2: creates the host HWND and kicks off WebView2 child controller
// init via `ionWebView2Start` (webview/controller.cpp). The async init
// chain runs through the Win32 message pump (PeekMessageW in poll.c).

#include "../state.h"
#include "../utf8.h"
#include "../internal.h"
#include "../../bridge.h"
#include "../../common/protoReg.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const wchar_t kIonClassName[] = L"IonMainWindow";
static int s_classRegistered = 0;

// Matches lifecycle.c's secondary→primary deep-link forward marker. Kept
// as a file-local constant; if more COPYDATA channels appear we'll lift
// this to internal.h.
#define ION_COPYDATA_DEEPLINK  0x494f4e44  /* 'IOND' */

// Window proc:
//   input messages       → input/input.c (surfaces, webview forwarding, IME)
//   WM_SIZE / DPI / MOVE → composition tree + webview bounds
//   WM_ION_TRAY_CB       → tray icon callback (Shell_NotifyIcon → tray.c)
//   WM_ION_NOTIFY_CB     → notification balloon callback (→ notify.c)
//   WM_CLOSE/WM_DESTROY  → tear down WebView2 + PostQuitMessage
//
// Tray + notify route their Shell_NotifyIcon callbacks here because
// HWND_MESSAGE windows don't reliably receive them on Win10/11.
static LRESULT CALLBACK ionWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    LRESULT handled;
    if (hwnd == s_mainHwnd && ionWinHandleInput(hwnd, msg, wParam, lParam, &handled)) return handled;
    switch (msg) {
        case WM_SIZE:
            if (wParam == SIZE_MINIMIZED) return 0;
            ionCompClientResized((int)(short)LOWORD(lParam),
                                 (int)(short)HIWORD(lParam));
            return 0;
        case WM_DPICHANGED: {
            const RECT *r = (const RECT *)lParam;
            RECT before, after;
            GetClientRect(hwnd, &before);
            SetWindowPos(hwnd, NULL, r->left, r->top, r->right - r->left, r->bottom - r->top,
                         SWP_NOZORDER | SWP_NOACTIVATE);
            GetClientRect(hwnd, &after);
            if (EqualRect(&before, &after)) ionCompDpiChanged();
            return 0;
        }
        case WM_MOVE:
            ionWebView2ParentMoved();
            return 0;
        case WM_GETOBJECT:
            if (ionWebView2HostAutomation(hwnd, wParam, lParam, &handled)) return handled;
            return DefWindowProcW(hwnd, msg, wParam, lParam);
        case WM_ION_TRAY_CB:
            // wParam = uID (1 = tray), lParam = mouse msg (e.g., WM_LBUTTONUP).
            ionTrayHandleCallback((UINT)lParam);
            return 0;
        case WM_ION_NOTIFY_CB:
            // wParam = uID (2 = notify), lParam = NIN_* balloon event code.
            ionNotifyHandleCallback((UINT)lParam);
            return 0;
        case WM_HOTKEY: {
            // wParam = hotkey id (from ionRegisterHotkey), lParam packs
            // modifiers+vk (we don't need either — id is enough).
            char buf[16];
            snprintf(buf, sizeof(buf), "%u", (unsigned)wParam);
            ionEnqueueMessage("hotkey", buf);
            return 0;
        }
        case WM_COPYDATA: {
            // Secondary ion instance forwarding a deep link URL — see
            // lifecycle.c forwardToPrimaryAndExit. Payload is UTF-8 string,
            // NUL-terminated. Enqueue as "deeplink" IPC + raise window.
            COPYDATASTRUCT *cds = (COPYDATASTRUCT *)lParam;
            if (cds != NULL && cds->dwData == ION_COPYDATA_DEEPLINK && cds->lpData != NULL) {
                ionEnqueueMessage("deeplink", (const char *)cds->lpData);
                ShowWindow(s_mainHwnd, SW_SHOWNORMAL);
                SetForegroundWindow(s_mainHwnd);
            }
            return TRUE;
        }
        case WM_CLOSE:
            DestroyWindow(hwnd);
            return 0;
        case WM_DESTROY:
            if (hwnd == s_mainHwnd) {
                ionWebView2RevokeDrop(hwnd);
                ionWebView2DetachAutomation(hwnd);
                ionWebView2Shutdown();
                ionCompShutdown();
                s_mainHwnd = NULL;
                PostQuitMessage(0);
            }
            return 0;
        default:
            return DefWindowProcW(hwnd, msg, wParam, lParam);
    }
}

static int ensureWindowClass(void) {
    if (s_classRegistered) return 1;
    if (s_hInstance == NULL) return 0;

    WNDCLASSEXW wc = {0};
    wc.cbSize        = sizeof(WNDCLASSEXW);
    wc.style         = CS_HREDRAW | CS_VREDRAW;
    wc.lpfnWndProc   = ionWndProc;
    wc.hInstance     = s_hInstance;
    wc.hCursor       = LoadCursorW(NULL, IDC_ARROW);
    wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
    wc.lpszClassName = kIonClassName;

    if (RegisterClassExW(&wc) == 0) return 0;
    s_classRegistered = 1;
    return 1;
}

int ionOpen(const char *title, int width, int height, const char *url) {
    if (s_mainHwnd != NULL) ionClose();
    if (!ensureWindowClass()) return 0;

    // Freeze custom-protocol registry — no more registerStaticProtocol /
    // registerAssetScope calls past this point. ionBuildEnvOptions reads
    // the now-immutable registry inside ionWebView2Start below.
    ionProtoFreeze();

    UINT dpi = GetDpiForSystem();
    int w = MulDiv(width  > 0 ? width  : 1280, (int)dpi, 96);
    int h = MulDiv(height > 0 ? height : 720,  (int)dpi, 96);

    wchar_t *wtitle = ionUtf8ToWide(title && title[0] ? title : "ion");
    if (wtitle == NULL) return 0;

    HWND hwnd = CreateWindowExW(
        0,
        kIonClassName,
        wtitle,
        WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT, CW_USEDEFAULT,
        w, h,
        NULL, NULL,
        s_hInstance,
        NULL
    );
    free(wtitle);

    if (hwnd == NULL) return 0;
    s_mainHwnd = hwnd;
    if (!ionCompInit(hwnd)) {
        DestroyWindow(hwnd);
        s_mainHwnd = NULL;
        return 0;
    }
    ionWebView2RegisterDrop(hwnd);
    ShowWindow(hwnd, SW_SHOW);
    UpdateWindow(hwnd);

    // Kick off WebView2 init — async, will complete via the message pump.
    // A 0 return here means the loader DLL is missing or the runtime isn't
    // installed; we still keep the window open so the user can see a clear
    // failure surface (white window + stderr message) rather than nothing.
    ionWebView2Start(hwnd, url);

    // Replay any cold-start deep link captured in ionInit. The IPC queue
    // persists across runLoop entry, so this fires when MS-side listeners
    // get drained for the first time. Matches mac's NSAppleEventManager
    // behavior where queued AppleEvents fire on first run-loop pump.
    if (s_coldStartUrl[0] != '\0') {
        ionEnqueueMessage("deeplink", s_coldStartUrl);
        s_coldStartUrl[0] = '\0';
    }
    return 1;
}

void ionClose(void) {
    if (s_mainHwnd != NULL) {
        // WM_DESTROY handler will call ionWebView2Shutdown + clear s_mainHwnd.
        DestroyWindow(s_mainHwnd);
        s_mainHwnd = NULL;
    }
}

HWND ionGetMainHwnd(void) {
    return s_mainHwnd;
}

// ---- Bundle resource path -------------------------------------------------
//
// On macOS this returns Contents/Resources/ inside the .app bundle, or "" in
// dev mode. Windows has no bundle concept — convention is to look in a
// `resources/` subfolder next to the .exe.

static char s_resourcePath[MAX_PATH * 4] = {0};  // ample room for UTF-8

msString ionResourcePath(void) {
    if (s_resourcePath[0] != 0) return cStringToMs(s_resourcePath);

    wchar_t exePath[MAX_PATH];
    DWORD n = GetModuleFileNameW(NULL, exePath, MAX_PATH);
    if (n == 0 || n >= MAX_PATH) return MS_EMPTY_STRING;

    // Strip filename to keep directory.
    for (DWORD i = n; i > 0; i--) {
        if (exePath[i - 1] == L'\\' || exePath[i - 1] == L'/') {
            exePath[i] = 0;
            break;
        }
    }

    // Append "resources" subfolder.
    wcsncat_s(exePath, MAX_PATH, L"resources", _TRUNCATE);

    // Only return path if directory exists; matches macOS "" fallback in dev.
    DWORD attrs = GetFileAttributesW(exePath);
    if (attrs == INVALID_FILE_ATTRIBUTES || !(attrs & FILE_ATTRIBUTE_DIRECTORY)) {
        s_resourcePath[0] = 0;
        return MS_EMPTY_STRING;
    }

    int needed = WideCharToMultiByte(CP_UTF8, 0, exePath, -1,
                                     s_resourcePath, sizeof(s_resourcePath),
                                     NULL, NULL);
    if (needed <= 0) { s_resourcePath[0] = 0; return MS_EMPTY_STRING; }
    return cStringToMs(s_resourcePath);
}

// ---- Multi-window stubs ---------------------------------------------------
//
// Windows multi-window port is deferred — these keep the cross-compile link
// step happy while macOS implements the real registry. Apps using only the
// legacy ionOpen/ionClose path are unaffected.

IonWindowId ionCreateWindow(const char *label, const char *title,
                            int width, int height, const char *url, int flags) {
    (void)label; (void)flags;
    return ionOpen(title, width, height, url) ? 0 : ION_WINDOW_INVALID;
}

void ionCloseWindow(IonWindowId id) {
    (void)id;
    ionClose();
}

int ionWindowCount(void) {
    return s_mainHwnd ? 1 : 0;
}

void ionEvalJSWindow(IonWindowId id, const char *js) {
    (void)id;
    ionEvalJS(js);
}

IonWindowId ionMessageWindowId(void) {
    return ION_WINDOW_INVALID;
}

void ionShowWindow(IonWindowId id)                          { (void)id; }
void ionHideWindow(IonWindowId id)                          { (void)id; }
void ionFocusWindow(IonWindowId id)                         { (void)id; }
void ionMinimizeWindow(IonWindowId id)                      { (void)id; }
void ionMaximizeWindow(IonWindowId id)                      { (void)id; }
void ionSetWindowTitle(IonWindowId id, const char *t)       { (void)id; (void)t; }
void ionSetWindowSize(IonWindowId id, int w, int h)         { (void)id; (void)w; (void)h; }
void ionSetWindowPosition(IonWindowId id, int x, int y)     { (void)id; (void)x; (void)y; }
void ionSetWindowAlwaysOnTop(IonWindowId id, int on)        { (void)id; (void)on; }
void ionSetWindowDecorations(IonWindowId id, int on)        { (void)id; (void)on; }
void ionSetWindowContentProtected(IonWindowId id, int on)   { (void)id; ionSetContentProtected(on); }
msString    ionFileOpenWindow(IonWindowId id)               { (void)id; return ionFileOpen(); }
IonWindowId ionWindowEventId(void)                          { return ION_WINDOW_INVALID; }
int         ionWindowEventType(void)                        { return 0; }
