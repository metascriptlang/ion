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
#include "../common/windowRegistry.h"

#ifdef __cplusplus
extern "C" {
#endif

HWND        ionGetMainHwnd(void);
IonWindowId ionGetMainWindowId(void);
HWND        ionWinHwnd(IonWindowId id);

int   ionCompInit(HWND hwnd);
void  ionCompShutdown(void);
void *ionCompDevice(void);
void  ionCompCommit(void);

void    ionWebView2CloseWindow(IonWindowId win);
void    ionWebView2ParentMoved(IonWindowId win);
HCURSOR ionWebView2Cursor(int id);
int     ionWebView2LastPointerTarget(void);

void    ionWebView2RegisterDrop(HWND host);
void    ionWebView2RevokeDrop(HWND host);
int     ionWebView2HostAutomation(HWND host, WPARAM wParam, LPARAM lParam, LRESULT *result);
void    ionWebView2DetachAutomation(HWND host);

int  ionWinHandleInput(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam, LRESULT *result);
void ionWinKeyFlush(void);
void ionWinPushResize(void);

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
