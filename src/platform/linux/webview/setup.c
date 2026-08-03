// Ion Linux — WebKitGTK webview setup + bootstrap injection + IPC wiring.
//
// Phase 2 + 4.5 entry point. Three things happen here:
//   1. Acquire (or create) the shared WebKitWebContext and register custom
//      URI scheme handlers on it BEFORE any view is created (WebKitGTK ties
//      scheme registration to the context for its lifetime — same constraint
//      as tauri-runtime-wry/src/lib.rs:5121).
//   2. Build a WebKitWebView with a UserContentManager.
//   3. Inject the bootstrap user-script (defines window.__ion__) + attach
//      the script-message-received handler (in webview/messaging.c) + the
//      decide-policy nav handler (in webview/nav.c).
//
// Pattern reference: wry src/webkitgtk/mod.rs (verified against the dev
// branch of tauri-apps/wry, May 2026). Ion is C, not Rust, so we call the
// same WebKit APIs directly via gobject_introspection's C bindings.

#include "../state.h"
#include "../internal.h"
#include "../../common/invokekey.h"
#include "../../common/bootstrap.h"

#include <webkit2/webkit2.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

// Forward decls for the helpers defined alongside this file.
static void injectBootstrapScript(WebKitUserContentManager *ucm);

WebKitWebView *ionSetupWebview(GtkWindow *parent) {
    if (parent == NULL) return NULL;

    // Acquire the default WebKitWebContext. WebKitGTK has one process-wide
    // context by default; we install custom URI scheme handlers on it before
    // any view spawns under it.
    WebKitWebContext *ctx = webkit_web_context_get_default();
    ionInstallSchemeHandlers(ctx);

    // Build the user content manager — owns injected scripts + the
    // script-message-received signal that ion uses for JS→MS IPC.
    WebKitUserContentManager *ucm = webkit_user_content_manager_new();

    // Inject the bootstrap user-script that defines window.__ion__. Same
    // template as macOS + Windows (common/bootstrap.c); only the native-post
    // line differs per platform.
    injectBootstrapScript(ucm);

    // Attach the IPC handler — defined in webview/messaging.c. Registers
    // "ion" as a script message channel.
    ionAttachMessageHandler(ucm);

    // Build the view with the configured content manager + default context.
    s_webView = WEBKIT_WEB_VIEW(g_object_new(
        WEBKIT_TYPE_WEB_VIEW,
        "web-context", ctx,
        "user-content-manager", ucm,
        NULL));

    // DevTools env-gate (matches mac WKPreferences + Win
    // ICoreWebView2Settings.AreDevToolsEnabled). Off by default, on when
    // ION_DEVTOOLS is truthy.
    WebKitSettings *settings = webkit_web_view_get_settings(s_webView);
    const char *envDev = getenv("ION_DEVTOOLS");
    gboolean devtools = FALSE;
    if (envDev != NULL && envDev[0] != '\0') {
        if (envDev[0] == '1' ||
            strcasecmp(envDev, "true") == 0 ||
            strcasecmp(envDev, "yes")  == 0 ||
            strcasecmp(envDev, "on")   == 0) {
            devtools = TRUE;
        }
    }
    webkit_settings_set_enable_developer_extras(settings, devtools);

    // Attach the nav handler (webview/nav.c) before the parent attaches the
    // view — so decide-policy fires for the initial load too.
    ionAttachNavHandler(s_webView);

    // Pack into the GtkWindow. WebKitWebView is a GtkWidget — gtk_container_add
    // makes it fill the window.
    gtk_container_add(GTK_CONTAINER(parent), GTK_WIDGET(s_webView));
    gtk_widget_show(GTK_WIDGET(s_webView));

    return s_webView;
}

// --- Bootstrap user-script injection -----------------------------------------
//
// Identical bootstrap template as mac + win (driven by common/bootstrap.c).
// The Linux-specific transport line uses
// `window.webkit.messageHandlers.ion.postMessage(envelope)` — same shape as
// macOS WKScriptMessageHandler.

static void injectBootstrapScript(WebKitUserContentManager *ucm) {
    char *jsBuf = ion_build_bootstrap_js(
        ion_invoke_key(),
        "window.webkit.messageHandlers.ion.postMessage(envelope);"
    );
    if (jsBuf == NULL) return;

    WebKitUserScript *script = webkit_user_script_new(
        jsBuf,
        WEBKIT_USER_CONTENT_INJECT_TOP_FRAME,  // main frame only — defense-in-depth
        WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START,
        NULL, NULL);

    webkit_user_content_manager_add_script(ucm, script);
    webkit_user_script_unref(script);
    free(jsBuf);
}
