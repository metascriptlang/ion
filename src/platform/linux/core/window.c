#include "../state.h"
#include "../internal.h"
#include "../../bridge.h"
#include "../../common/frameClock.h"
#include "../../common/webviewRegistry.h"
#include "../../common/windowEvents.h"
#include "../../common/windowRegistry.h"

#include <gtk/gtk.h>
#include <linux/limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

static const char kMainLabel[] = "main";

IonLinuxWindowState *ionLinuxWindowState(IonWindowId id) {
    IonWindowSlot *slot = ion_registry_get(id);
    return slot ? (IonLinuxWindowState *)slot->platformState : NULL;
}

IonLinuxWindowState *ionLinuxWindowForToplevel(GtkWidget *toplevel) {
    for (IonWindowId i = ion_registry_next(ION_WINDOW_INVALID);
         i != ION_WINDOW_INVALID;
         i = ion_registry_next(i)) {
        IonLinuxWindowState *st = ionLinuxWindowState(i);
        if (st && st->window == toplevel) return st;
    }
    return NULL;
}

static void refreshMainWindow(void) {
    IonWindowId pick = ion_registry_find(kMainLabel);
    if (pick == ION_WINDOW_INVALID) pick = ion_registry_next(ION_WINDOW_INVALID);
    IonLinuxWindowState *st = ionLinuxWindowState(pick);
    s_mainWindow = st ? st->window : NULL;
}

void ionLinuxSyncFrameState(IonLinuxWindowState *st) {
    int visible = gtk_widget_get_visible(st->window) && !st->iconified;
    ion_frame_window_state(st->id, gtk_window_is_active(GTK_WINDOW(st->window)), visible);
}

static gboolean onDeleteEvent(GtkWidget *widget, GdkEvent *event, gpointer data) {
    (void)widget; (void)event; (void)data;
    s_quitRequested = 1;
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

static gboolean onWindowState(GtkWidget *w, GdkEventWindowState *e, gpointer data) {
    (void)w;
    IonLinuxWindowState *st = (IonLinuxWindowState *)data;
    if (e->changed_mask & GDK_WINDOW_STATE_ICONIFIED) {
        st->iconified = (e->new_window_state & GDK_WINDOW_STATE_ICONIFIED) != 0;
        ionLinuxSyncFrameState(st);
    }
    return FALSE;
}

static gboolean onConfigure(GtkWidget *w, GdkEventConfigure *e, gpointer data) {
    (void)w; (void)e;
    ion_wevt_push(((IonLinuxWindowState *)data)->id, ION_EVT_MOVED);
    return FALSE;
}

static void onRootAllocate(GtkWidget *w, GdkRectangle *a, gpointer data) {
    (void)w; (void)a;
    IonLinuxWindowState *st = (IonLinuxWindowState *)data;
    ionLinuxPushResize(st);
    ion_wevt_push(st->id, ION_EVT_RESIZED);
}

IonWindowId ionCreateWindow(const char *label, const char *title,
                            int width, int height, int flags) {
    IonWindowId winId = ion_registry_alloc(label);
    if (winId == ION_WINDOW_INVALID) return ION_WINDOW_INVALID;

    IonLinuxWindowState *st = (IonLinuxWindowState *)calloc(1, sizeof *st);
    if (!st) {
        ion_registry_free(winId);
        return ION_WINDOW_INVALID;
    }
    st->id = winId;

    ionLinuxInstallInput();

    GtkWidget *win = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    st->window = win;
    gtk_window_set_title(GTK_WINDOW(win), (title && title[0]) ? title : "ion");
    gtk_window_set_default_size(GTK_WINDOW(win), width > 0 ? width : 1280,
                                                 height > 0 ? height : 720);
    gtk_window_set_resizable(GTK_WINDOW(win), (flags & ION_WIN_RESIZABLE) != 0);
    gtk_window_set_decorated(GTK_WINDOW(win), (flags & ION_WIN_DECORATIONS) != 0);
    if (flags & ION_WIN_ALWAYS_ON_TOP) gtk_window_set_keep_above(GTK_WINDOW(win), TRUE);
    if (flags & ION_WIN_CENTERED)      gtk_window_set_position(GTK_WINDOW(win), GTK_WIN_POS_CENTER);
    if (flags & ION_WIN_FULLSCREEN)    gtk_window_fullscreen(GTK_WINDOW(win));
    if (flags & ION_WIN_TRANSPARENT) {
        GdkVisual *rgba = gdk_screen_get_rgba_visual(gtk_widget_get_screen(win));
        if (rgba) gtk_widget_set_visual(win, rgba);
        gtk_widget_set_app_paintable(win, TRUE);
    }

    st->root = gtk_fixed_new();
    gtk_container_add(GTK_CONTAINER(win), st->root);
    gtk_widget_show(st->root);

    gtk_widget_add_events(win, GDK_POINTER_MOTION_MASK | GDK_BUTTON_PRESS_MASK
        | GDK_BUTTON_RELEASE_MASK | GDK_SCROLL_MASK | GDK_SMOOTH_SCROLL_MASK
        | GDK_KEY_PRESS_MASK | GDK_KEY_RELEASE_MASK | GDK_LEAVE_NOTIFY_MASK
        | GDK_ENTER_NOTIFY_MASK | GDK_FOCUS_CHANGE_MASK | GDK_STRUCTURE_MASK);
    g_signal_connect(win, "delete-event", G_CALLBACK(onDeleteEvent), st);
    g_signal_connect(win, "notify::is-active", G_CALLBACK(onActiveChanged), st);
    g_signal_connect(win, "window-state-event", G_CALLBACK(onWindowState), st);
    g_signal_connect(win, "configure-event", G_CALLBACK(onConfigure), st);
    g_signal_connect(st->root, "size-allocate", G_CALLBACK(onRootAllocate), st);

    ionLinuxAttachInput(st);

    IonWindowSlot *slot = ion_registry_get(winId);
    slot->platformState = st;
    ion_frame_window_open(winId);
    refreshMainWindow();

    if (flags & ION_WIN_VISIBLE) gtk_widget_show(win);
    ionLinuxSyncFrameState(st);

    // Replay cold-start deep link (captured in lifecycle.c::captureColdStartUrl).
    // Queued after window creation so MS-side listen() callbacks see it on the
    // first poll. Mirrors Mac + Win "deeplink" cold-start replay.
    if (s_coldStartUrl[0] != '\0') {
        ionEnqueueMessage("deeplink", s_coldStartUrl);
        s_coldStartUrl[0] = '\0';  // one-shot — secondary launches arrive via DBus
    }
    return winId;
}

void ionCloseWindow(IonWindowId winId) {
    IonWindowSlot *slot = ion_registry_get(winId);
    if (!slot) return;
    IonLinuxWindowState *st = (IonLinuxWindowState *)slot->platformState;

    for (int wv = ion_webview_next(-1); wv != ION_WEBVIEW_INVALID; wv = ion_webview_next(wv)) {
        if (ion_webview_get(wv)->window == winId) ionWebviewRelease(wv);
    }

    ion_frame_window_close(winId);
    if (st) {
        g_signal_handlers_disconnect_by_data(st->window, st);
        g_signal_handlers_disconnect_by_data(st->root, st);
        ionLinuxDetachInput(st);
        gtk_widget_destroy(st->window);
        free(st);
    }
    slot->platformState = NULL;
    ion_registry_free(winId);
    refreshMainWindow();
}

int ionWindowCount(void) {
    return ion_registry_count();
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
    GdkWindow *gw = st ? gtk_widget_get_window(st->window) : NULL;
    if (!gw) return;
    const char *name = "default";
    switch (cursor) {
        case ION_CURSOR_HAND:     name = "pointer"; break;
        case ION_CURSOR_IBEAM:    name = "text"; break;
        case ION_CURSOR_CROSS:    name = "crosshair"; break;
        case ION_CURSOR_RESIZE_H: name = "ew-resize"; break;
        case ION_CURSOR_RESIZE_V: name = "ns-resize"; break;
        default: break;
    }
    GdkCursor *c = gdk_cursor_new_from_name(gdk_window_get_display(gw), name);
    gdk_window_set_cursor(gw, c);
    if (c) g_object_unref(c);
}

void ionShowWindow(IonWindowId id) {
    IonLinuxWindowState *st = ionLinuxWindowState(id);
    if (!st) return;
    gtk_widget_show(st->window);
    ionLinuxSyncFrameState(st);
}

void ionHideWindow(IonWindowId id) {
    IonLinuxWindowState *st = ionLinuxWindowState(id);
    if (!st) return;
    gtk_widget_hide(st->window);
    ionLinuxSyncFrameState(st);
}

void ionFocusWindow(IonWindowId id) {
    IonLinuxWindowState *st = ionLinuxWindowState(id);
    if (st) gtk_window_present(GTK_WINDOW(st->window));
}

void ionMinimizeWindow(IonWindowId id) {
    IonLinuxWindowState *st = ionLinuxWindowState(id);
    if (st) gtk_window_iconify(GTK_WINDOW(st->window));
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
    if (st) gtk_window_resize(GTK_WINDOW(st->window), width > 0 ? width : 1,
                                                      height > 0 ? height : 1);
}

void ionSetWindowPosition(IonWindowId id, int x, int y) {
    IonLinuxWindowState *st = ionLinuxWindowState(id);
    if (st) gtk_window_move(GTK_WINDOW(st->window), x, y);
}

void ionSetWindowAlwaysOnTop(IonWindowId id, int on) {
    IonLinuxWindowState *st = ionLinuxWindowState(id);
    if (st) gtk_window_set_keep_above(GTK_WINDOW(st->window), on ? TRUE : FALSE);
}

void ionSetWindowDecorations(IonWindowId id, int on) {
    IonLinuxWindowState *st = ionLinuxWindowState(id);
    if (st) gtk_window_set_decorated(GTK_WINDOW(st->window), on ? TRUE : FALSE);
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
    return st ? gtk_widget_get_allocated_width(st->root) * gtk_widget_get_scale_factor(st->root) : 0;
}

int ionWindowPixelHeight(IonWindowId id) {
    IonLinuxWindowState *st = ionLinuxWindowState(id);
    return st ? gtk_widget_get_allocated_height(st->root) * gtk_widget_get_scale_factor(st->root) : 0;
}
