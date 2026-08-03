// Ion Linux — shared state + helper declarations.
//
// Mirrors macos/state.h + windows/state.h: globals live in state.c, other
// implementation files reach them via these extern declarations.

#ifndef ION_LINUX_STATE_H
#define ION_LINUX_STATE_H

#include <gtk/gtk.h>
#include <webkit2/webkit2.h>

#ifdef __cplusplus
extern "C" {
#endif

// Main GtkWindow* — destroyed on window close (NULL after).
extern GtkWidget *s_mainWindow;

// WebKitWebView* — set up in webview/setup.c during ionOpen. NULL before
// open or after destroy.
extern WebKitWebView *s_webView;

// Cold-start deep link URL extracted from /proc/self/cmdline at ionInit
// time. window.c replays this as a "deeplink" IPC after the window opens
// (mirrors Mac NSAppleEventManager + Win core/lifecycle.c WM_COPYDATA flow).
// Empty when the app was not launched with a URL arg.
extern char s_coldStartUrl[2048];

// Convenience shim around the common IPC queue. Lets Linux callers avoid
// re-typing the (name, payload) push pattern.
void ionEnqueueMessage(const char *name, const char *payload);

#ifdef __cplusplus
}
#endif

#endif
