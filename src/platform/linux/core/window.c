#include "../state.h"
#include "../internal.h"
#include "../../bridge.h"
#include "../../common/frameClock.h"
#include "../../common/webviewRegistry.h"
#include "../../common/windowEvents.h"
#include "../../common/windowRegistry.h"

#include <gtk/gtk.h>
#include <linux/limits.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

static const char kMainLabel[] = "main";
static int s_hadWindow;

IonLinuxWindowState *ionLinuxWindowState(IonWindowId id) {
    IonWindowSlot *slot = ion_registry_get(id);
    return slot ? (IonLinuxWindowState *)slot->platformState : NULL;
}

static void refreshMainWindow(void) {
    IonLinuxWindowState *pick = ionLinuxWindowState(ion_registry_find(kMainLabel));
    for (IonWindowId i = ion_registry_next(ION_WINDOW_INVALID);
         pick == NULL && i != ION_WINDOW_INVALID;
         i = ion_registry_next(i)) {
        pick = ionLinuxWindowState(i);
    }
    s_mainWindow = pick ? pick->window : NULL;
}

static GdkSurface *surfaceOf(IonLinuxWindowState *st) {
    return gtk_native_get_surface(GTK_NATIVE(st->window));
}

double ionLinuxScale(IonLinuxWindowState *st) {
    GdkSurface *surface = surfaceOf(st);
    return surface ? gdk_surface_get_scale(surface) : 1.0;
}

void ionLinuxPresentMain(void) {
    if (s_mainWindow != NULL) gtk_window_present(GTK_WINDOW(s_mainWindow));
}

void ionLinuxSyncFrameState(IonLinuxWindowState *st) {
    int visible = gtk_widget_get_visible(st->window) && !st->iconified;
    ion_frame_window_state(st->id, gtk_window_is_active(GTK_WINDOW(st->window)), visible);
}

static gboolean onCloseRequest(GtkWindow *window, gpointer data) {
    (void)window;
    IonLinuxWindowState *st = (IonLinuxWindowState *)data;
    ion_wevt_push(st->id, ION_EVT_CLOSE_REQUESTED);
    return TRUE;
}

static void onActiveChanged(GObject *obj, GParamSpec *pspec, gpointer data) {
    (void)obj; (void)pspec;
    IonLinuxWindowState *st = (IonLinuxWindowState *)data;
    ionLinuxSyncFrameState(st);
    ion_wevt_push(st->id, gtk_window_is_active(GTK_WINDOW(st->window))
                              ? ION_EVT_FOCUSED : ION_EVT_BLURRED);
    ionLinuxUpdateContentFocus(st);
}

static void onFocusWidgetChanged(GObject *obj, GParamSpec *pspec, gpointer data) {
    (void)obj; (void)pspec;
    ionLinuxUpdateContentFocus((IonLinuxWindowState *)data);
}

static void onToplevelState(GObject *surface, GParamSpec *pspec, gpointer data) {
    (void)pspec;
    IonLinuxWindowState *st = (IonLinuxWindowState *)data;
    st->iconified = (gdk_toplevel_get_state(GDK_TOPLEVEL(surface)) & GDK_TOPLEVEL_STATE_MINIMIZED) != 0;
    ionLinuxSyncFrameState(st);
}

static void onSurfaceScale(GObject *surface, GParamSpec *pspec, gpointer data) {
    (void)surface; (void)pspec;
    IonLinuxWindowState *st = (IonLinuxWindowState *)data;
    ionLinuxPushResize(st, gtk_widget_get_width(st->root), gtk_widget_get_height(st->root));
}

static void onRealize(GtkWidget *window, gpointer data) {
    (void)window;
    IonLinuxWindowState *st = (IonLinuxWindowState *)data;
    GdkSurface *surface = surfaceOf(st);
    g_signal_connect(surface, "notify::state", G_CALLBACK(onToplevelState), st);
    g_signal_connect(surface, "notify::scale", G_CALLBACK(onSurfaceScale), st);
}

static void onMap(GtkWidget *window, gpointer data) {
    IonLinuxWindowState *st = (IonLinuxWindowState *)data;
    if (st->wantAbove) ionLinuxX11SetAbove(window, 1);
}

static void applyWantedSize(IonLinuxWindowState *st, int rootW, int rootH) {
    GtkWindow *win = GTK_WINDOW(st->window);
    if (st->wantW <= 0 || rootW <= 0 || rootH <= 0 || gtk_window_is_maximized(win) || gtk_window_is_fullscreen(win)) return;
    int outerW = gtk_widget_get_width(st->window), outerH = gtk_widget_get_height(st->window);
    int w = st->wantW + (outerW - rootW), h = st->wantH + (outerH - rootH);
    st->wantW = st->wantH = 0;
    if (w != outerW || h != outerH) gtk_window_set_default_size(win, w, h);
}

static void onProbeResize(GtkDrawingArea *area, int width, int height, gpointer data) {
    (void)area;
    IonLinuxWindowState *st = (IonLinuxWindowState *)data;
    applyWantedSize(st, width, height);
    ionLinuxPushResize(st, width, height);
    ion_wevt_push(st->id, ION_EVT_RESIZED);
}

static void installTransparentCss(void) {
    static int installed;
    if (installed) return;
    installed = 1;
    GtkCssProvider *css = gtk_css_provider_new();
    gtk_css_provider_load_from_string(css, "window.ionTransparent { background: transparent; }");
    gtk_style_context_add_provider_for_display(gdk_display_get_default(),
        GTK_STYLE_PROVIDER(css), GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    g_object_unref(css);
}

IonWindowId ionCreateWindow(const char *label, const char *title,
                            int width, int height, int flags) {
    ionLinuxReleaseReadDestroyed();
    IonWindowId winId = ion_registry_alloc(label);
    if (winId == ION_WINDOW_INVALID) return ION_WINDOW_INVALID;

    IonLinuxWindowState *st = (IonLinuxWindowState *)calloc(1, sizeof *st);
    if (!st) {
        ion_registry_free(winId);
        return ION_WINDOW_INVALID;
    }
    st->id = winId;

    GtkWidget *win = gtk_window_new();
    st->window = win;
    gtk_window_set_title(GTK_WINDOW(win), (title && title[0]) ? title : "ion");
    st->wantW = width > 0 ? width : 1280;
    st->wantH = height > 0 ? height : 720;
    gtk_window_set_default_size(GTK_WINDOW(win), st->wantW, st->wantH);
    gtk_window_set_resizable(GTK_WINDOW(win), (flags & ION_WIN_RESIZABLE) != 0);
    gtk_window_set_decorated(GTK_WINDOW(win), (flags & ION_WIN_DECORATIONS) != 0);
    if (flags & ION_WIN_ALWAYS_ON_TOP) st->wantAbove = 1;
    if (flags & ION_WIN_CENTERED) {
        fprintf(stderr, "[ion] createWindow: Centered ignored, GTK4 cannot place a window; the compositor does\n");
    }
    if (flags & ION_WIN_FULLSCREEN) gtk_window_fullscreen(GTK_WINDOW(win));
    if (flags & ION_WIN_TRANSPARENT) {
        installTransparentCss();
        gtk_widget_add_css_class(win, "ionTransparent");
    }

    // The probe's resize signal is the only size notification GTK4 gives a plain
    // container; the overlay gives the root the probe's size.
    GtkWidget *overlay = gtk_overlay_new();
    GtkWidget *probe = gtk_drawing_area_new();
    gtk_widget_set_can_target(probe, FALSE);
    gtk_widget_set_hexpand(probe, TRUE);
    gtk_widget_set_vexpand(probe, TRUE);
    gtk_overlay_set_child(GTK_OVERLAY(overlay), probe);
    st->root = gtk_fixed_new();
    gtk_overlay_add_overlay(GTK_OVERLAY(overlay), st->root);
    gtk_overlay_set_clip_overlay(GTK_OVERLAY(overlay), st->root, TRUE);
    gtk_window_set_child(GTK_WINDOW(win), overlay);

    g_signal_connect(win, "close-request", G_CALLBACK(onCloseRequest), st);
    g_signal_connect(win, "notify::is-active", G_CALLBACK(onActiveChanged), st);
    g_signal_connect(win, "notify::focus-widget", G_CALLBACK(onFocusWidgetChanged), st);
    g_signal_connect(win, "realize", G_CALLBACK(onRealize), st);
    g_signal_connect(win, "map", G_CALLBACK(onMap), st);
    g_signal_connect(probe, "resize", G_CALLBACK(onProbeResize), st);

    ionLinuxAttachInput(st);

    IonWindowSlot *slot = ion_registry_get(winId);
    slot->platformState = st;
    s_hadWindow = 1;
    ion_frame_window_open(winId);
    refreshMainWindow();

    if (flags & ION_WIN_VISIBLE) gtk_window_present(GTK_WINDOW(win));
    ionLinuxSyncFrameState(st);

    if (s_coldStartUrl[0] != '\0') {
        ionEnqueueMessage("deeplink", s_coldStartUrl);
        s_coldStartUrl[0] = '\0';
    }
    return winId;
}

void ionCloseWindow(IonWindowId winId) {
    IonWindowSlot *slot = ion_registry_get(winId);
    if (!slot || !slot->platformState) return;
    IonLinuxWindowState *st = (IonLinuxWindowState *)slot->platformState;

    for (int wv = ion_webview_next(-1); wv != ION_WEBVIEW_INVALID; wv = ion_webview_next(wv)) {
        if (ion_webview_get(wv)->window == winId) ionWebviewRelease(wv);
    }

    ion_frame_window_close(winId);
    GdkSurface *surface = surfaceOf(st);
    if (surface) g_signal_handlers_disconnect_by_data(surface, st);
    g_signal_handlers_disconnect_by_data(st->window, st);
    ionLinuxFrameDetach(st);
    ionLinuxDetachInput(st);
    gtk_window_destroy(GTK_WINDOW(st->window));
    free(st);
    slot->platformState = NULL;
    ion_wevt_push(winId, ION_EVT_DESTROYED);
    refreshMainWindow();
}

int ionLinuxAllWindowsClosed(void) {
    return s_hadWindow && ionWindowCount() == 0;
}

int ionWindowCount(void) {
    int n = 0;
    for (IonWindowId i = ion_registry_next(ION_WINDOW_INVALID); i != ION_WINDOW_INVALID; i = ion_registry_next(i)) {
        if (ionLinuxWindowState(i)) n++;
    }
    return n;
}

GtkWidget *ionGetMainWindow(void) {
    return s_mainWindow;
}

static char s_resourcePath[PATH_MAX * 2] = {0};

msString ionResourcePath(void) {
    if (s_resourcePath[0] != 0) return cStringToMs(s_resourcePath);

    char exePath[PATH_MAX];
    ssize_t n = readlink("/proc/self/exe", exePath, sizeof(exePath) - 1);
    if (n <= 0) return MS_EMPTY_STRING;
    exePath[n] = '\0';

    char *slash = strrchr(exePath, '/');
    if (slash == NULL) return MS_EMPTY_STRING;
    *(slash + 1) = '\0';

    snprintf(s_resourcePath, sizeof(s_resourcePath), "%sresources", exePath);

    struct stat st;
    if (stat(s_resourcePath, &st) != 0 || !S_ISDIR(st.st_mode)) {
        s_resourcePath[0] = 0;
        return MS_EMPTY_STRING;
    }
    return cStringToMs(s_resourcePath);
}

void *ionWindowDevice(IonWindowId id) { (void)id; return NULL; }

void *ionWindowRoot(IonWindowId id) {
    IonLinuxWindowState *st = ionLinuxWindowState(id);
    return st ? (void *)st->root : NULL;
}

void ionWindowCommit(IonWindowId id) { (void)id; }

void ionWindowFocusContent(IonWindowId id) {
    IonLinuxWindowState *st = ionLinuxWindowState(id);
    if (!st) return;
    gtk_window_set_focus(GTK_WINDOW(st->window), NULL);
    ionLinuxUpdateContentFocus(st);
}

void ionWindowSetCursor(IonWindowId id, int cursor) {
    IonLinuxWindowState *st = ionLinuxWindowState(id);
    if (!st) return;
    const char *name = NULL;
    switch (cursor) {
        case ION_CURSOR_HAND:     name = "pointer"; break;
        case ION_CURSOR_IBEAM:    name = "text"; break;
        case ION_CURSOR_CROSS:    name = "crosshair"; break;
        case ION_CURSOR_RESIZE_H: name = "ew-resize"; break;
        case ION_CURSOR_RESIZE_V: name = "ns-resize"; break;
        default: break;
    }
    gtk_widget_set_cursor_from_name(st->root, name);
}

void ionShowWindow(IonWindowId id) {
    IonLinuxWindowState *st = ionLinuxWindowState(id);
    if (!st) return;
    gtk_window_present(GTK_WINDOW(st->window));
    ionLinuxSyncFrameState(st);
}

void ionHideWindow(IonWindowId id) {
    IonLinuxWindowState *st = ionLinuxWindowState(id);
    if (!st) return;
    gtk_widget_set_visible(st->window, FALSE);
    ionLinuxSyncFrameState(st);
}

void ionFocusWindow(IonWindowId id) {
    IonLinuxWindowState *st = ionLinuxWindowState(id);
    if (st) gtk_window_present(GTK_WINDOW(st->window));
}

void ionMinimizeWindow(IonWindowId id) {
    IonLinuxWindowState *st = ionLinuxWindowState(id);
    if (st) gtk_window_minimize(GTK_WINDOW(st->window));
}

void ionMaximizeWindow(IonWindowId id) {
    IonLinuxWindowState *st = ionLinuxWindowState(id);
    if (st) gtk_window_maximize(GTK_WINDOW(st->window));
}

void ionSetWindowTitle(IonWindowId id, const char *title) {
    IonLinuxWindowState *st = ionLinuxWindowState(id);
    if (st) gtk_window_set_title(GTK_WINDOW(st->window), title ? title : "");
}

void ionSetWindowSize(IonWindowId id, int width, int height) {
    IonLinuxWindowState *st = ionLinuxWindowState(id);
    if (!st) return;
    st->wantW = width > 0 ? width : 1;
    st->wantH = height > 0 ? height : 1;
    if (gtk_widget_get_mapped(st->window)) {
        applyWantedSize(st, gtk_widget_get_width(st->root), gtk_widget_get_height(st->root));
    } else {
        gtk_window_set_default_size(GTK_WINDOW(st->window), st->wantW, st->wantH);
    }
}

void ionSetWindowPosition(IonWindowId id, int x, int y) {
    (void)x; (void)y;
    if (!ionLinuxWindowState(id)) return;
    fprintf(stderr, "[ion] setPosition: unavailable, GTK4 has no gtk_window_move and Wayland gives clients no global position\n");
}

void ionSetWindowAlwaysOnTop(IonWindowId id, int on) {
    IonLinuxWindowState *st = ionLinuxWindowState(id);
    if (!st) return;
    st->wantAbove = on ? 1 : 0;
    if (!gtk_widget_get_mapped(st->window)) return;
    if (!ionLinuxX11SetAbove(st->window, st->wantAbove)) {
        fprintf(stderr, "[ion] setAlwaysOnTop: unavailable on Wayland, xdg-shell has no stacking request; run with GDK_BACKEND=x11\n");
    }
}

void ionWindowRequestUserAttention(IonWindowId id, int type) {
    if (!ionLinuxWindowState(id) || type == ION_ATTENTION_NONE) return;
    fprintf(stderr, "[ion] requestUserAttention: GTK 4 has no urgency request (gtk_window_set_urgency_hint was removed)\n");
}

void ionBeep(void) {
    gdk_display_beep(gdk_display_get_default());
}

void ionSetWindowDecorations(IonWindowId id, int on) {
    IonLinuxWindowState *st = ionLinuxWindowState(id);
    if (!st) return;
    if (gtk_widget_get_mapped(st->window) && gtk_widget_get_width(st->root) > 0) {
        st->wantW = gtk_widget_get_width(st->root);
        st->wantH = gtk_widget_get_height(st->root);
    }
    gtk_window_set_decorated(GTK_WINDOW(st->window), on ? TRUE : FALSE);
}

void ionSetWindowContentProtected(IonWindowId id, int on) {
    (void)id;
    ionSetContentProtected(on);
}

msString ionFileOpenWindow(IonWindowId id) {
    (void)id;
    return ionFileOpen();
}

int ionWindowPixelWidth(IonWindowId id) {
    IonLinuxWindowState *st = ionLinuxWindowState(id);
    return st ? (int)lround(gtk_widget_get_width(st->root) * ionLinuxScale(st)) : 0;
}

int ionWindowPixelHeight(IonWindowId id) {
    IonLinuxWindowState *st = ionLinuxWindowState(id);
    return st ? (int)lround(gtk_widget_get_height(st->root) * ionLinuxScale(st)) : 0;
}
