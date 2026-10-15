#include "../state.h"
#include "../utf8.h"
#include "../internal.h"
#include "../../bridge.h"
#include "../../common/protoReg.h"
#include "../../common/frameClock.h"
#include "../../common/windowRegistry.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const wchar_t kIonClassName[] = L"IonMainWindow";
static int s_classRegistered = 0;
static int s_active = 1;
static int s_minimized = 0;
static int s_cloaked = 0;
static HWINEVENTHOOK s_cloakHook = NULL;
static IonWindowId s_mainId = ION_WINDOW_INVALID;

static int s_resizable = 1;

static DWORD frameStyle(int decorated, int resizable) {
    DWORD style = decorated ? WS_OVERLAPPEDWINDOW : WS_POPUP;
    if (!resizable) style &= ~(DWORD)(WS_THICKFRAME | WS_MAXIMIZEBOX);
    return style;
}

// Outer size of a window whose client area is cw x ch device-independent
// pixels at `dpi`. winit window_state.rs:507-511 (AdjustWindowRectExForDpi on
// the window's style, exstyle and DPI). No AdjustWindowRectEx fallback: this
// file already needs GetDpiForSystem/GetDpiForWindow, which arrive in the
// same Windows 10 1607 as AdjustWindowRectExForDpi.
static void clientToOuter(DWORD style, DWORD exStyle, UINT dpi, int cw, int ch, int *ow, int *oh) {
    RECT r = {0, 0, MulDiv(cw, (int)dpi, 96), MulDiv(ch, (int)dpi, 96)};
    AdjustWindowRectExForDpi(&r, style, FALSE, exStyle, dpi);
    *ow = r.right - r.left;
    *oh = r.bottom - r.top;
}

static void setClientSize(HWND hwnd, int cw, int ch) {
    if (IsZoomed(hwnd) || IsIconic(hwnd)) ShowWindow(hwnd, SW_RESTORE);
    int ow, oh;
    clientToOuter((DWORD)GetWindowLongPtrW(hwnd, GWL_STYLE), (DWORD)GetWindowLongPtrW(hwnd, GWL_EXSTYLE),
                  GetDpiForWindow(hwnd), cw > 0 ? cw : 1, ch > 0 ? ch : 1, &ow, &oh);
    SetWindowPos(hwnd, NULL, 0, 0, ow, oh, SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
}

static void reportFrameWindow(void) {
    ion_frame_window_state(s_mainId, s_active, !s_minimized && !s_cloaked);
}

static void CALLBACK onCloak(HWINEVENTHOOK hook, DWORD event, HWND hwnd, LONG idObject,
                             LONG idChild, DWORD thread, DWORD time) {
    (void)hook; (void)idChild; (void)thread; (void)time;
    if (hwnd != s_mainHwnd || idObject != OBJID_WINDOW) return;
    s_cloaked = event == EVENT_OBJECT_CLOAKED;
    reportFrameWindow();
}

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
        case WM_ACTIVATE:
            s_active = LOWORD(wParam) != WA_INACTIVE;
            reportFrameWindow();
            return DefWindowProcW(hwnd, msg, wParam, lParam);
        case WM_SIZE:
            s_minimized = wParam == SIZE_MINIMIZED;
            reportFrameWindow();
            if (s_minimized) return 0;
            ionWinPushResize();
            return 0;
        case WM_DPICHANGED: {
            const RECT *r = (const RECT *)lParam;
            RECT before, after;
            GetClientRect(hwnd, &before);
            SetWindowPos(hwnd, NULL, r->left, r->top, r->right - r->left, r->bottom - r->top,
                         SWP_NOZORDER | SWP_NOACTIVATE);
            GetClientRect(hwnd, &after);
            if (EqualRect(&before, &after)) ionWinPushResize();
            return 0;
        }
        case WM_MOVE:
            ionWebView2ParentMoved(s_mainId);
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
                if (s_cloakHook != NULL) { UnhookWinEvent(s_cloakHook); s_cloakHook = NULL; }
                s_cloaked = 0;
                ionWebView2RevokeDrop(hwnd);
                ionWebView2DetachAutomation(hwnd);
                ionWebView2CloseWindow(s_mainId);
                ionCompShutdown();
                ion_frame_window_close(s_mainId);
                ion_registry_free(s_mainId);
                s_mainId = ION_WINDOW_INVALID;
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

IonWindowId ionCreateWindow(const char *label, const char *title, int width, int height, int flags) {
    if (s_mainHwnd != NULL) {
        fprintf(stderr, "[ion] ionCreateWindow '%s': Windows hosts one window today\n", label ? label : "");
        return ION_WINDOW_INVALID;
    }
    if (!ensureWindowClass()) return ION_WINDOW_INVALID;
    IonWindowId id = ion_registry_alloc(label);
    if (id == ION_WINDOW_INVALID) return ION_WINDOW_INVALID;

    DWORD style = frameStyle((flags & ION_WIN_DECORATIONS) != 0, (flags & ION_WIN_RESIZABLE) != 0);
    DWORD exStyle = (flags & ION_WIN_ALWAYS_ON_TOP) ? WS_EX_TOPMOST : 0;
    s_resizable = (flags & ION_WIN_RESIZABLE) != 0;
    int w, h;
    clientToOuter(style, exStyle, GetDpiForSystem(),
                  width > 0 ? width : 1280, height > 0 ? height : 720, &w, &h);

    wchar_t *wtitle = ionUtf8ToWide(title && title[0] ? title : "ion");
    if (wtitle == NULL) { ion_registry_free(id); return ION_WINDOW_INVALID; }
    HWND hwnd = CreateWindowExW(exStyle, kIonClassName, wtitle, style,
                                CW_USEDEFAULT, CW_USEDEFAULT, w, h, NULL, NULL, s_hInstance, NULL);
    free(wtitle);
    if (hwnd == NULL) { ion_registry_free(id); return ION_WINDOW_INVALID; }

    // The window's own DPI is known only now (a secondary monitor may differ
    // from the system DPI): size the client area again with it.
    setClientSize(hwnd, width > 0 ? width : 1280, height > 0 ? height : 720);

    s_mainHwnd = hwnd;
    s_mainId = id;
    if (!ionCompInit(hwnd)) {
        DestroyWindow(hwnd);
        return ION_WINDOW_INVALID;
    }
    ion_frame_window_open(id);
    ionWebView2RegisterDrop(hwnd);
    s_cloakHook = SetWinEventHook(EVENT_OBJECT_CLOAKED, EVENT_OBJECT_UNCLOAKED, NULL, onCloak,
                                  GetCurrentProcessId(), 0, WINEVENT_OUTOFCONTEXT);
    if (s_cloakHook == NULL) fprintf(stderr, "[ion] cloak hook failed (%lu)\n", GetLastError());
    if (flags & ION_WIN_VISIBLE) {
        ShowWindow(hwnd, SW_SHOW);
        UpdateWindow(hwnd);
    }
    ionWinPushResize();

    if (s_coldStartUrl[0] != '\0') {
        ionEnqueueMessage("deeplink", s_coldStartUrl);
        s_coldStartUrl[0] = '\0';
    }
    return id;
}

void ionCloseWindow(IonWindowId id) {
    HWND hwnd = ionWinHwnd(id);
    if (hwnd != NULL) DestroyWindow(hwnd);
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

IonWindowId ionGetMainWindowId(void) {
    return s_mainId;
}

HWND ionWinHwnd(IonWindowId id) {
    return id != ION_WINDOW_INVALID && id == s_mainId ? s_mainHwnd : NULL;
}

int ionWindowCount(void) {
    return s_mainHwnd ? 1 : 0;
}

int ionWindowPixelWidth(IonWindowId id) {
    RECT rc;
    HWND hwnd = ionWinHwnd(id);
    return hwnd && GetClientRect(hwnd, &rc) ? rc.right - rc.left : 0;
}

int ionWindowPixelHeight(IonWindowId id) {
    RECT rc;
    HWND hwnd = ionWinHwnd(id);
    return hwnd && GetClientRect(hwnd, &rc) ? rc.bottom - rc.top : 0;
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
