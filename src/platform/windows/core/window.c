#include "../state.h"
#include "../utf8.h"
#include "../internal.h"
#include "../../bridge.h"
#include "../../common/protoReg.h"
#include "../../common/frameClock.h"
#include "../../common/windowRegistry.h"
#include "../../common/windowEvents.h"

#include <dwmapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

static const wchar_t kIonClassName[] = L"IonMainWindow";
static const char kMainLabel[] = "main";
static int s_classRegistered = 0;
#define ION_MODAL_TIMER 1
static HWINEVENTHOOK s_cloakHook = NULL;

IonWinWindow *ionWinWindow(IonWindowId id) {
    IonWindowSlot *slot = ion_registry_get(id);
    IonWinWindow *w = slot ? (IonWinWindow *)slot->platformState : NULL;
    return w != NULL && w->hwnd != NULL ? w : NULL;
}

static IonWinWindow *windowOfHwnd(HWND hwnd) {
    for (IonWindowId id = ion_registry_next(ION_WINDOW_INVALID); id != ION_WINDOW_INVALID; id = ion_registry_next(id)) {
        IonWinWindow *w = ionWinWindow(id);
        if (w != NULL && w->hwnd == hwnd) return w;
    }
    return NULL;
}

static IonWinWindow *windowOfProc(HWND hwnd) {
    return (IonWinWindow *)GetWindowLongPtrW(hwnd, GWLP_USERDATA);
}

static void refreshMainWindow(void) {
    IonWinWindow *pick = ionWinWindow(ion_registry_find(kMainLabel));
    for (IonWindowId id = ion_registry_next(ION_WINDOW_INVALID); pick == NULL && id != ION_WINDOW_INVALID;
         id = ion_registry_next(id))
        pick = ionWinWindow(id);
    HWND main = pick ? pick->hwnd : NULL;
    if (main == s_mainHwnd) return;
    s_mainHwnd = main;
    ionTrayRehost(main);
    ionNotifyRehost();
}

void ionWinReleaseDestroyed(IonWindowId id) {
    IonWindowSlot *slot = ion_registry_get(id);
    IonWinWindow *w = slot ? (IonWinWindow *)slot->platformState : NULL;
    if (w == NULL || w->hwnd != NULL) return;
    free(w);
    ion_registry_free(id);
}

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

static BOOL systemAppsDark(void) {
    DWORD light = 1, size = sizeof light;
    LSTATUS rc = RegGetValueW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
                              L"AppsUseLightTheme", RRF_RT_REG_DWORD, NULL, &light, &size);
    return rc == ERROR_SUCCESS && light == 0;
}

static void applySystemTheme(HWND hwnd) {
    BOOL dark = systemAppsDark();
    HRESULT hr = DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, &dark, sizeof dark);
    if (FAILED(hr)) fprintf(stderr, "[ion] dark title bar: DwmSetWindowAttribute failed (0x%08lx)\n", (unsigned long)hr);
}

static void reportFrameWindow(IonWinWindow *w) {
    ion_frame_window_state(w->id, w->active, !w->minimized && !w->cloaked);
}

static void CALLBACK onCloak(HWINEVENTHOOK hook, DWORD event, HWND hwnd, LONG idObject,
                             LONG idChild, DWORD thread, DWORD time) {
    (void)hook; (void)idChild; (void)thread; (void)time;
    if (idObject != OBJID_WINDOW) return;
    IonWinWindow *w = windowOfHwnd(hwnd);
    if (w == NULL) return;
    w->cloaked = event == EVENT_OBJECT_CLOAKED;
    reportFrameWindow(w);
}

static void installCloakHook(void) {
    if (s_cloakHook != NULL) return;
    s_cloakHook = SetWinEventHook(EVENT_OBJECT_CLOAKED, EVENT_OBJECT_UNCLOAKED, NULL, onCloak,
                                  GetCurrentProcessId(), 0, WINEVENT_OUTOFCONTEXT);
    if (s_cloakHook == NULL) fprintf(stderr, "[ion] cloak hook failed (%lu)\n", GetLastError());
}

static void destroyed(IonWinWindow *w) {
    HWND hwnd = w->hwnd;
    ionWebView2RevokeDrop(hwnd);
    ionWebView2DetachAutomation(hwnd, &w->uia);
    ionWebView2CloseWindow(w->id);
    ionCompDetach(w);
    ion_frame_window_close(w->id);
    ion_wevt_push(w->id, ION_EVT_DESTROYED);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
    w->hwnd = NULL;
    refreshMainWindow();
    if (ionWindowCount() == 0 && s_cloakHook != NULL) {
        UnhookWinEvent(s_cloakHook);
        s_cloakHook = NULL;
    }
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
//   WM_CLOSE/WM_DESTROY  → tear down this window's WebView2 and compositor
//
// Tray + notify route their Shell_NotifyIcon callbacks here because
// HWND_MESSAGE windows don't reliably receive them on Win10/11.
static LRESULT CALLBACK ionWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    LRESULT handled;
    IonWinWindow *w = windowOfProc(hwnd);
    if (w != NULL && ionWinHandleInput(w, msg, wParam, lParam, &handled)) return handled;
    switch (msg) {
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
        default:
            break;
    }
    if (w == NULL) return DefWindowProcW(hwnd, msg, wParam, lParam);
    switch (msg) {
        case WM_ACTIVATE:
            w->active = LOWORD(wParam) != WA_INACTIVE;
            if (w->active != w->focused) {
                w->focused = w->active;
                ion_wevt_push(w->id, w->focused ? ION_EVT_FOCUSED : ION_EVT_BLURRED);
            }
            reportFrameWindow(w);
            return DefWindowProcW(hwnd, msg, wParam, lParam);
        case WM_SIZE:
            w->minimized = wParam == SIZE_MINIMIZED;
            reportFrameWindow(w);
            if (w->minimized) return 0;
            ionWinPushResize(w);
            ion_wevt_push(w->id, ION_EVT_RESIZED);
            return 0;
        case WM_DPICHANGED: {
            const RECT *r = (const RECT *)lParam;
            RECT before, after;
            GetClientRect(hwnd, &before);
            SetWindowPos(hwnd, NULL, r->left, r->top, r->right - r->left, r->bottom - r->top,
                         SWP_NOZORDER | SWP_NOACTIVATE);
            GetClientRect(hwnd, &after);
            if (EqualRect(&before, &after)) ionWinPushResize(w);
            return 0;
        }
        case WM_ENTERSIZEMOVE:
        case WM_ENTERMENULOOP:
            SetTimer(hwnd, ION_MODAL_TIMER, USER_TIMER_MINIMUM, NULL);
            return DefWindowProcW(hwnd, msg, wParam, lParam);
        case WM_EXITSIZEMOVE:
        case WM_EXITMENULOOP:
            KillTimer(hwnd, ION_MODAL_TIMER);
            return DefWindowProcW(hwnd, msg, wParam, lParam);
        case WM_TIMER:
            if (wParam != ION_MODAL_TIMER) return DefWindowProcW(hwnd, msg, wParam, lParam);
            ionModalPump();
            return 0;
        case WM_MOVE:
            ionWebView2ParentMoved(w->id);
            if (!IsIconic(hwnd)) ion_wevt_push(w->id, ION_EVT_MOVED);
            return 0;
        case WM_SETTINGCHANGE:
            if (lParam != 0 && lstrcmpW((LPCWSTR)lParam, L"ImmersiveColorSet") == 0) applySystemTheme(hwnd);
            return DefWindowProcW(hwnd, msg, wParam, lParam);
        case WM_GETOBJECT:
            if (ionWebView2HostAutomation(hwnd, &w->uia, wParam, lParam, &handled)) return handled;
            return DefWindowProcW(hwnd, msg, wParam, lParam);
        case WM_CLOSE:
            // The app closes the window (ionCloseWindow) unless it prevents the close.
            ion_wevt_push(w->id, ION_EVT_CLOSE_REQUESTED);
            return 0;
        case WM_DESTROY:
            destroyed(w);
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

static IonWinWindow *allocWindow(const char *label) {
    ionWinReleaseDestroyed(ion_registry_find(label));
    IonWindowId id = ion_registry_alloc(label);
    if (id == ION_WINDOW_INVALID) {
        fprintf(stderr, "[ion] ionCreateWindow '%s': label empty, taken or too long, or %d windows open\n",
                label ? label : "", ION_MAX_WINDOWS);
        return NULL;
    }
    IonWinWindow *w = (IonWinWindow *)calloc(1, sizeof *w);
    if (w == NULL) {
        ion_registry_free(id);
        return NULL;
    }
    w->id = id;
    w->active = 1;
    w->cursor = ION_CURSOR_ARROW;
    ion_registry_get(id)->platformState = w;
    return w;
}

static void freeWindow(IonWinWindow *w) {
    ion_registry_free(w->id);
    free(w);
}

IonWindowId ionCreateWindow(const char *label, const char *title, int width, int height, int flags) {
    if (!ensureWindowClass()) return ION_WINDOW_INVALID;
    IonWinWindow *w = allocWindow(label);
    if (w == NULL) return ION_WINDOW_INVALID;

    DWORD style = frameStyle((flags & ION_WIN_DECORATIONS) != 0, (flags & ION_WIN_RESIZABLE) != 0);
    DWORD exStyle = (flags & ION_WIN_ALWAYS_ON_TOP) ? WS_EX_TOPMOST : 0;
    w->resizable = (flags & ION_WIN_RESIZABLE) != 0;
    int ow, oh;
    clientToOuter(style, exStyle, GetDpiForSystem(),
                  width > 0 ? width : 1280, height > 0 ? height : 720, &ow, &oh);

    wchar_t *wtitle = ionUtf8ToWide(title && title[0] ? title : "ion");
    if (wtitle == NULL) { freeWindow(w); return ION_WINDOW_INVALID; }
    HWND hwnd = CreateWindowExW(exStyle, kIonClassName, wtitle, style,
                                CW_USEDEFAULT, CW_USEDEFAULT, ow, oh, NULL, NULL, s_hInstance, NULL);
    free(wtitle);
    if (hwnd == NULL) { freeWindow(w); return ION_WINDOW_INVALID; }
    applySystemTheme(hwnd);

    // The window's own DPI is known only now (a secondary monitor may differ
    // from the system DPI): size the client area again with it.
    setClientSize(hwnd, width > 0 ? width : 1280, height > 0 ? height : 720);

    w->hwnd = hwnd;
    if (!ionCompAttach(w)) {
        w->hwnd = NULL;
        DestroyWindow(hwnd);
        freeWindow(w);
        return ION_WINDOW_INVALID;
    }
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, (LONG_PTR)w);
    ion_frame_window_open(w->id);
    ionWebView2RegisterDrop(hwnd);
    installCloakHook();
    refreshMainWindow();
    if (flags & ION_WIN_VISIBLE) {
        ShowWindow(hwnd, SW_SHOW);
        UpdateWindow(hwnd);
    }
    ionWinPushResize(w);

    if (s_coldStartUrl[0] != '\0') {
        ionEnqueueMessage("deeplink", s_coldStartUrl);
        s_coldStartUrl[0] = '\0';
    }
    return w->id;
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

HWND ionWinHwnd(IonWindowId id) {
    IonWinWindow *w = ionWinWindow(id);
    return w ? w->hwnd : NULL;
}

int ionWindowCount(void) {
    int n = 0;
    for (IonWindowId id = ion_registry_next(ION_WINDOW_INVALID); id != ION_WINDOW_INVALID; id = ion_registry_next(id))
        if (ionWinWindow(id) != NULL) n++;
    return n;
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

void ionShowWindow(IonWindowId id)     { HWND h = ionWinHwnd(id); if (h) ShowWindow(h, SW_SHOW); }
void ionHideWindow(IonWindowId id)     { HWND h = ionWinHwnd(id); if (h) ShowWindow(h, SW_HIDE); }
void ionMinimizeWindow(IonWindowId id) { HWND h = ionWinHwnd(id); if (h) ShowWindow(h, SW_MINIMIZE); }
void ionMaximizeWindow(IonWindowId id) { HWND h = ionWinHwnd(id); if (h) ShowWindow(h, SW_MAXIMIZE); }

// A background process cannot always take the foreground; winit
// window.rs:1832-1867 synthesises an Alt key press to get the permission.
void ionFocusWindow(IonWindowId id) {
    HWND h = ionWinHwnd(id);
    if (h == NULL || !IsWindowVisible(h) || IsIconic(h) || GetForegroundWindow() == h) return;
    if (SetForegroundWindow(h) && GetForegroundWindow() == h) return;
    INPUT in[2] = {{0}};
    in[0].type = in[1].type = INPUT_KEYBOARD;
    in[0].ki.wVk = in[1].ki.wVk = VK_MENU;
    in[1].ki.dwFlags = KEYEVENTF_KEYUP;
    SendInput(2, in, sizeof(INPUT));
    SetForegroundWindow(h);
}

void ionSetWindowTitle(IonWindowId id, const char *t) {
    HWND h = ionWinHwnd(id);
    wchar_t *w = h ? ionUtf8ToWide(t ? t : "") : NULL;
    if (w == NULL) return;
    SetWindowTextW(h, w);
    free(w);
}

void ionSetWindowSize(IonWindowId id, int w, int h) {
    HWND hwnd = ionWinHwnd(id);
    if (hwnd) setClientSize(hwnd, w, h);
}

// The outer (frame) top-left, in virtual-screen pixels: winit window.rs:560-585
// set_outer_position, which also leaves the maximized state.
void ionSetWindowPosition(IonWindowId id, int x, int y) {
    HWND h = ionWinHwnd(id);
    if (h == NULL) return;
    if (IsZoomed(h)) ShowWindow(h, SW_RESTORE);
    SetWindowPos(h, NULL, x, y, 0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
}

// winit window_state.rs:405-423 (HWND_TOPMOST / HWND_NOTOPMOST).
void ionSetWindowAlwaysOnTop(IonWindowId id, int on) {
    HWND h = ionWinHwnd(id);
    if (h) SetWindowPos(h, on ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0, 0,
                        SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
}

// Same two frames createWindow picks (caption + frame, or WS_POPUP). The
// client area keeps its size and screen position; a maximized or minimized
// window only has its frame refreshed. winit window_state.rs:496-514.
void ionSetWindowDecorations(IonWindowId id, int on) {
    IonWinWindow *w = ionWinWindow(id);
    if (w == NULL) return;
    HWND h = w->hwnd;
    const DWORD frame = WS_OVERLAPPEDWINDOW | WS_POPUP;
    DWORD old = (DWORD)GetWindowLongPtrW(h, GWL_STYLE);
    DWORD style = (old & ~frame) | frameStyle(on != 0, w->resizable);
    if (style == old) return;
    RECT client;
    GetClientRect(h, &client);
    POINT origin = {0, 0};
    ClientToScreen(h, &origin);
    SetWindowLongPtrW(h, GWL_STYLE, (LONG_PTR)style);
    UINT flags = SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED;
    RECT r = {origin.x, origin.y, origin.x + client.right, origin.y + client.bottom};
    if (IsZoomed(h) || IsIconic(h)) {
        flags |= SWP_NOMOVE | SWP_NOSIZE;
    } else {
        AdjustWindowRectExForDpi(&r, style, FALSE, (DWORD)GetWindowLongPtrW(h, GWL_EXSTYLE), GetDpiForWindow(h));
    }
    SetWindowPos(h, NULL, r.left, r.top, r.right - r.left, r.bottom - r.top, flags);
}

void ionSetWindowContentProtected(IonWindowId id, int on) {
    HWND h = ionWinHwnd(id);
    if (h) SetWindowDisplayAffinity(h, on ? WDA_EXCLUDEFROMCAPTURE : WDA_NONE);
}

msString ionFileOpenWindow(IonWindowId id) {
    HWND h = ionWinHwnd(id);
    return h ? ionWinFileOpen(h) : MS_EMPTY_STRING;
}
