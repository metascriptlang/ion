// Ion Windows — platform-internal forward declarations.
//
// bridge.h (one level up) is the public C API consumed by MS code.
// internal.h is the platform-private surface — symbols implemented in
// one .c file and called from another .c file in the same platform layer.
// Mirrors src/platform/macos/internal.h's role.

#ifndef ION_WINDOWS_INTERNAL_H
#define ION_WINDOWS_INTERNAL_H

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include "../common/strconv.h"  // cStringToMs / MS_EMPTY_STRING

#ifdef __cplusplus
extern "C" {
#endif

// core/window.c
HWND       ionGetMainHwnd(void);

// webview/controller.cpp — extern "C" entry points called from C code.
// `ionWebView2Start` kicks off async WebView2 init bound to the main HWND
// and pointed at `url`. Returns 1 on init request OK (controller becomes
// ready later via the message pump), 0 on synchronous failure (loader DLL
// missing, runtime not installed). Caller (core/window.c) calls this after
// CreateWindowExW.
int  ionWebView2Start(HWND hwnd, const char *url);
// Tear down: closes controller, releases COM refs, NULLs s_webview2State.
void ionWebView2Shutdown(void);
// Resize the webview to match the host HWND client area. Called from the
// WndProc on WM_SIZE.
void ionWebView2Resize(int width, int height);

// chrome/tray.c + chrome/notify.c — Shell_NotifyIcon callbacks route to the
// main HWND (HWND_MESSAGE windows don't reliably receive these on Win10/11).
// WndProc in core/window.c dispatches WM_APP+1 (tray) and WM_APP+2 (notify)
// here. Each handler receives the lParam event (mouse msg or NIN_* code) and
// the uID is implicit (one per module).
#define WM_ION_TRAY_CB    (WM_APP + 1)
#define WM_ION_NOTIFY_CB  (WM_APP + 2)

void ionTrayHandleCallback(UINT event);
void ionNotifyHandleCallback(UINT event);

#ifdef __cplusplus
}
#endif

#endif
