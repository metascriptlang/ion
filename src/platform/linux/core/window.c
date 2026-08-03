// Ion Linux — window lifecycle: ionOpen, ionClose, ionResourcePath.
//
// Phase 2: GtkWindow hosts a WebKitWebView child. ionSetupWebview (in
// webview/setup.c) installs the custom URI scheme handlers on the default
// WebContext + builds + attaches the view; ionOpen then loads the URL.

#include "../state.h"
#include "../internal.h"
#include "../../bridge.h"
#include "../../common/protoReg.h"

#include <gtk/gtk.h>
#include <webkit2/webkit2.h>
#include <linux/limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

// Window destroy → clear pointer + exit GTK main loop. poll.c noticing
// s_mainWindow == NULL is what surfaces "quit" to MS-side runLoop.
static void onWindowDestroy(GtkWidget *widget, gpointer data) {
    (void)widget; (void)data;
    s_mainWindow = NULL;
    gtk_main_quit();
}

int ionOpen(const char *title, int width, int height, const char *url) {
    if (s_mainWindow != NULL) ionClose();

    // Freeze custom-protocol registry — no more registerStaticProtocol /
    // registerAssetScope calls past this point. ionSetupWebview reads the
    // now-immutable registry to install URI schemes on the WebContext.
    ionProtoFreeze();

    int w = width  > 0 ? width  : 1280;
    int h = height > 0 ? height : 720;

    s_mainWindow = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_title(GTK_WINDOW(s_mainWindow),
                         (title && title[0]) ? title : "ion");
    gtk_window_set_default_size(GTK_WINDOW(s_mainWindow), w, h);
    g_signal_connect(s_mainWindow, "destroy", G_CALLBACK(onWindowDestroy), NULL);

    // Build + attach the WebKitWebView (also wires URI schemes, bootstrap
    // script, IPC handler, nav delegate). Returns NULL on failure.
    if (ionSetupWebview(GTK_WINDOW(s_mainWindow)) == NULL) {
        gtk_widget_destroy(s_mainWindow);
        s_mainWindow = NULL;
        return 0;
    }

    gtk_widget_show_all(s_mainWindow);

    // Kick off navigation to the requested URL.
    if (url != NULL && url[0] != '\0') {
        webkit_web_view_load_uri(s_webView, url);
    }

    // Replay cold-start deep link (captured in lifecycle.c::captureColdStartUrl).
    // Queued after window creation so MS-side listen() callbacks see it on the
    // first poll. Mirrors Mac + Win "deeplink" cold-start replay.
    if (s_coldStartUrl[0] != '\0') {
        ionEnqueueMessage("deeplink", s_coldStartUrl);
        s_coldStartUrl[0] = '\0';  // one-shot — secondary launches arrive via DBus
    }
    return 1;
}

void ionClose(void) {
    if (s_mainWindow != NULL) {
        gtk_widget_destroy(s_mainWindow);
        s_mainWindow = NULL;
        s_webView = NULL;  // webview is a child of the window; destroyed with it
    }
}

GtkWidget *ionGetMainWindow(void) {
    return s_mainWindow;
}

// ---- Resource path ----------------------------------------------------------
// Mirrors Windows' convention: <exe-dir>/resources/. AppImage layout
// (Phase 5) places resources at the same relative spot inside the squashfs
// root, so this works for portable runs + installed runs alike.

static char s_resourcePath[PATH_MAX * 2] = {0};

msString ionResourcePath(void) {
    if (s_resourcePath[0] != 0) return cStringToMs(s_resourcePath);

    char exePath[PATH_MAX];
    ssize_t n = readlink("/proc/self/exe", exePath, sizeof(exePath) - 1);
    if (n <= 0) return MS_EMPTY_STRING;
    exePath[n] = '\0';

    // Strip filename to keep directory.
    char *slash = strrchr(exePath, '/');
    if (slash == NULL) return MS_EMPTY_STRING;
    *(slash + 1) = '\0';  // keep trailing '/'

    snprintf(s_resourcePath, sizeof(s_resourcePath), "%sresources", exePath);

    // Only return path if directory exists; matches mac+win "" fallback in dev.
    struct stat st;
    if (stat(s_resourcePath, &st) != 0 || !S_ISDIR(st.st_mode)) {
        s_resourcePath[0] = 0;
        return MS_EMPTY_STRING;
    }
    return cStringToMs(s_resourcePath);
}

// ---- Multi-window stubs ---------------------------------------------------
//
// Linux multi-window port is deferred — these keep the cross-compile link
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
    return s_mainWindow ? 1 : 0;
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
