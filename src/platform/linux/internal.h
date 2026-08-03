// Ion Linux — platform-internal forward declarations.
//
// bridge.h (one level up) is the public C API consumed by MS code.
// internal.h is the platform-private surface — symbols implemented in one
// .c file and called from another .c file in the same platform layer.
// Mirrors src/platform/macos/internal.h + src/platform/windows/internal.h.

#ifndef ION_LINUX_INTERNAL_H
#define ION_LINUX_INTERNAL_H

#include <gtk/gtk.h>
#include <webkit2/webkit2.h>
#include "../common/strconv.h"  // cStringToMs / MS_EMPTY_STRING

#ifdef __cplusplus
extern "C" {
#endif

// core/window.c
GtkWidget *ionGetMainWindow(void);

// webview/setup.c — create + configure WebKitWebView, attach to container.
// Returns the new view (also stored in s_webView). Must be called AFTER
// ionProtoFreeze (custom URI schemes need to land on the WebContext before
// it's used). Returns NULL on failure.
WebKitWebView *ionSetupWebview(GtkWindow *parent);

// webview/protocol.c — install custom URI scheme handlers on the shared
// WebKitWebContext. MUST be called BEFORE any WebKitWebView is created;
// WebKitGTK ties the scheme registration to the context for its lifetime
// (cf. tauri-runtime-wry lib.rs:5121 — same constraint).
void ionInstallSchemeHandlers(WebKitWebContext *ctx);

// webview/messaging.c — attach script-message-received handler that gates
// on invoke_key + pushes (name, payload) onto the IPC queue.
void ionAttachMessageHandler(WebKitUserContentManager *ucm);

// webview/nav.c — connect decide-policy signal to apply ion_nav_decide
// rules (allow, external→gtk_show_uri, BLOCK for file://).
void ionAttachNavHandler(WebKitWebView *view);

#ifdef __cplusplus
}
#endif

#endif
