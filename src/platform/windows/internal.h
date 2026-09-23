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
void    ionWebView2SetBounds(int x, int y, int width, int height);
void    ionWebView2SetVisible(int visible);
void    ionWebView2SetTransparent(int transparent);
void    ionWebView2Focus(void);
void    ionWebView2ParentMoved(void);
void    ionWebView2SendMouse(UINT msg, WPARAM wParam, DWORD mouseData, int x, int y);
HCURSOR ionWebView2Cursor(void);

#define ION_COMP_ROUTE_NONE    (-1)
#define ION_COMP_ROUTE_WEBVIEW (-2)
int   ionCompInit(HWND hwnd);
void  ionCompShutdown(void);
void *ionCompWebviewVisual(void);
void  ionCompCommit(void);
void  ionCompClientResized(int width, int height);
void  ionCompDpiChanged(void);
int   ionCompRoute(int x, int y);
void  ionCompWebviewOrigin(int *x, int *y);
void  ionCompPointer(int surf, int type, int px, int py, double p1, double p2);
int   ionCompFocusedSurface(void);
void  ionCompFocusSurface(int surf, int hostHasFocus);
void  ionCompHostFocus(int gained);
int   ionCompImeRect(int surf, RECT *out);

int  ionWinHandleInput(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam, LRESULT *result);
void ionWinKeyFlush(void);
void ionWinImeReposition(void);

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
