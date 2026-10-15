#include "../state.h"
#include "../internal.h"
#include "../../bridge.h"
#include "../../common/invokekey.h"
#include "../../common/bootstrap.h"
#include "../../common/protoReg.h"
#include "../../common/webviewRegistry.h"

#include <math.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <strings.h>

static IonLinuxWebviewState *webviewState(IonWebviewId id) {
    IonWebviewSlot *slot = ion_webview_get(id);
    return slot ? (IonLinuxWebviewState *)slot->platformState : NULL;
}

static void injectBootstrapScript(WebKitUserContentManager *ucm, const char *label) {
    char *jsBuf = ion_build_bootstrap_js_w(
        ion_invoke_key(),
        label,
        "window.webkit.messageHandlers.ion.postMessage(envelope);"
    );
    if (jsBuf == NULL) return;

    WebKitUserScript *script = webkit_user_script_new(
        jsBuf,
        WEBKIT_USER_CONTENT_INJECT_TOP_FRAME,
        WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START,
        NULL, NULL);

    webkit_user_content_manager_add_script(ucm, script);
    webkit_user_script_unref(script);
    free(jsBuf);
}

IonWebviewId ionWebviewCreate(IonWindowId win, const char *label, const char *url) {
    if (ionLinuxWindowState(win) == NULL) return ION_WEBVIEW_INVALID;
    IonWebviewId id = ion_webview_alloc(label, win);
    if (id == ION_WEBVIEW_INVALID) return ION_WEBVIEW_INVALID;

    WebKitWebContext *ctx = webkit_web_context_get_default();
    if (!ionProtoIsFrozen()) {
        ionProtoFreeze();
        ionInstallSchemeHandlers(ctx);
    }

    WebKitUserContentManager *ucm = webkit_user_content_manager_new();
    injectBootstrapScript(ucm, label);
    ionAttachMessageHandler(ucm, id);

    IonLinuxWebviewState *st = (IonLinuxWebviewState *)calloc(1, sizeof *st);
    if (!st) {
        g_object_unref(ucm);
        ion_webview_free(id);
        return ION_WEBVIEW_INVALID;
    }
    st->view = WEBKIT_WEB_VIEW(g_object_new(
        WEBKIT_TYPE_WEB_VIEW,
        "web-context", ctx,
        "user-content-manager", ucm,
        NULL));
    g_object_ref_sink(st->view);
    g_object_unref(ucm);

    const char *envDev = getenv("ION_DEVTOOLS");
    gboolean devtools = envDev != NULL && (envDev[0] == '1'
        || strcasecmp(envDev, "true") == 0
        || strcasecmp(envDev, "yes")  == 0
        || strcasecmp(envDev, "on")   == 0);
    webkit_settings_set_enable_developer_extras(
        webkit_web_view_get_settings(st->view), devtools);

    ionAttachNavHandler(st->view);

    ion_webview_get(id)->platformState = st;

    if (url != NULL && url[0] != '\0') webkit_web_view_load_uri(st->view, url);
    return id;
}

void ionWebviewRelease(IonWebviewId id) {
    IonLinuxWebviewState *st = webviewState(id);
    if (!st) return;
    GtkWidget *node = GTK_WIDGET(st->view);
    GtkWidget *parent = gtk_widget_get_parent(node);
    if (parent != NULL && GTK_IS_FIXED(parent)) gtk_fixed_remove(GTK_FIXED(parent), node);
    else if (parent != NULL) gtk_widget_unparent(node);
    g_object_unref(st->view);
    free(st);
    ion_webview_free(id);
}

void *ionWebviewNode(IonWebviewId id) {
    IonLinuxWebviewState *st = webviewState(id);
    return st ? (void *)st->view : NULL;
}

// Assumes the app parents the node directly in the window's GtkFixed root; in any
// other container the node gets its size only.
void ionWebviewSetBounds(IonWebviewId id, int x, int y, int w, int h) {
    IonLinuxWebviewState *st = webviewState(id);
    if (!st) return;
    GtkWidget *node = GTK_WIDGET(st->view);
    IonLinuxWindowState *win = ionLinuxWindowState(ionWebviewWindow(id));
    double scale = win ? ionLinuxScale(win) : 1.0;
    st->x = x;
    st->y = y;
    gtk_widget_set_size_request(node, (int)lround(w / scale), (int)lround(h / scale));
    GtkWidget *parent = gtk_widget_get_parent(node);
    if (parent != NULL && GTK_IS_FIXED(parent)) {
        gtk_fixed_move(GTK_FIXED(parent), node, x / scale, y / scale);
    }
}

void ionWebviewSetVisible(IonWebviewId id, int visible) {
    IonLinuxWebviewState *st = webviewState(id);
    if (st) gtk_widget_set_visible(GTK_WIDGET(st->view), visible ? TRUE : FALSE);
}

void ionWebviewSetTransparent(IonWebviewId id, int transparent) {
    IonLinuxWebviewState *st = webviewState(id);
    if (!st) return;
    GdkRGBA bg = transparent ? (GdkRGBA){0, 0, 0, 0} : (GdkRGBA){1, 1, 1, 1};
    webkit_web_view_set_background_color(st->view, &bg);
}

void ionWebviewFocus(IonWebviewId id) {
    IonLinuxWebviewState *st = webviewState(id);
    if (!st) return;
    gtk_widget_grab_focus(GTK_WIDGET(st->view));
    IonLinuxWindowState *win = ionLinuxWindowState(ionWebviewWindow(id));
    if (win) ionLinuxUpdateContentFocus(win);
}

// The WebKitWebView is a real GtkWidget that receives pointer events itself: nothing to forward.
void ionWebviewForwardPointer(IonWebviewId id, int kind, double x, double y,
                              int button, double delta) {
    (void)id; (void)kind; (void)x; (void)y; (void)button; (void)delta;
}
