// ionWindowContentXid on X11, driven from C while msc cannot build an Ion app on Linux.
// contentXid.sh builds it against Ion's Linux sources and runs it under Xvfb.
// argv[1]: "x11" calls ionRequestX11 first; "plain" does not. argv[2] "header": a GtkHeaderBar titlebar,
// drawn by the client inside the toplevel, as GNOME does.
#include "platform/bridge.h"

#include <gtk/gtk.h>
#include <gdk/x11/gdkx.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

#ifdef ION_PROBE_VOID
// Void's Linux views (void src/platform/linux/window.c, built with VOID_GLES3), as Neon drives them.
#include "linux/window.h"
#include <GLES3/gl3.h>

static void voidClear(const VoidLinuxView *v) {
    voidLinuxViewMakeCurrent(v);
    glViewport(0, 0, v->w, v->h);
    glClearColor(0.0f, 1.0f, 0.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
    voidLinuxViewSwap(v);
    glFinish();
}
#endif

GtkWidget *ionGetMainWindow(void);

static int s_failures;
static int s_xError;

static void check(int ok, const char *what) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok) s_failures++;
}

static void pump(int ms) {
    gint64 until = g_get_monotonic_time() + ms * 1000;
    while (g_get_monotonic_time() < until) {
        while (g_main_context_iteration(NULL, FALSE)) {}
        g_usleep(2000);
    }
}

static int onXError(Display *dpy, XErrorEvent *e) {
    (void)dpy;
    s_xError = e->error_code;
    return 0;
}

static Window parentOf(Display *dpy, Window w) {
    Window root, parent, *children = NULL;
    unsigned n = 0;
    if (!XQueryTree(dpy, w, &root, &parent, &children, &n)) return 0;
    if (children) XFree(children);
    return parent;
}

static unsigned long pixelAt(Display *dpy, Window w, int x, int y) {
    XImage *img = XGetImage(dpy, w, x, y, 1, 1, AllPlanes, ZPixmap);
    if (img == NULL) return 0xdeadbeef;
    unsigned long p = XGetPixel(img, 0, 0) & 0xffffff;
    XDestroyImage(img);
    return p;
}

// The content window's geometry in its parent, read on a connection of the probe's own, as Void would.
static int geometry(Display *dpy, Window w, XWindowAttributes *a) {
    XSync(dpy, False);
    return XGetWindowAttributes(dpy, w, a);
}

int main(int argc, char **argv) {
    int optIn = argc > 1 && strcmp(argv[1], "x11") == 0;
    int header = argc > 2 && strcmp(argv[2], "header") == 0;
    if (optIn) {
        check(ionRequestX11() == 1, "ionRequestX11 returns 1 on an X server");
    } else if (!ionInit()) {
        printf("FAIL ionInit\n");
        return 1;
    }
    GdkDisplay *gdk = gdk_display_get_default();
    printf("backend %s, GDK_SCALE=%s, header bar %s\n", G_OBJECT_TYPE_NAME(gdk),
           getenv("GDK_SCALE") ? getenv("GDK_SCALE") : "-", header ? "yes" : "no");

    IonWindowId id = ionCreateWindow("main", "contentXid", 400, 300, ION_WIN_DEFAULT & ~ION_WIN_VISIBLE);
    if (header) gtk_window_set_titlebar(GTK_WINDOW(ionGetMainWindow()), gtk_header_bar_new());
    ionShowWindow(id);
    pump(800);
    int64_t xid = ionWindowContentXid(id);
    if (!GDK_IS_X11_DISPLAY(gdk)) {
        check(xid == 0, "not on X11: ionWindowContentXid returns 0");
        printf("%s, %d failure(s)\n", s_failures ? "RED" : "GREEN", s_failures);
        return s_failures ? 1 : 0;
    }
    check(xid != 0, "ionWindowContentXid returns an XID");
    check(ionWindowContentXid(id) == xid, "a second call returns the same XID");
    check(ionWindowContentXid(id + 7) == 0, "an invalid id returns 0");
    pump(300);

    Display *dpy = XOpenDisplay(NULL);
    XSetErrorHandler(onXError);
    GtkWidget *win = ionGetMainWindow();
    Window top = gdk_x11_surface_get_xid(gtk_native_get_surface(GTK_NATIVE(win)));
    check(parentOf(dpy, (Window)xid) == top, "the XID is a child of the toplevel");

    XWindowAttributes a, t;
    geometry(dpy, (Window)xid, &a);
    geometry(dpy, top, &t);
    int pw = ionWindowPixelWidth(id), ph = ionWindowPixelHeight(id);
    int scale = gdk_surface_get_scale_factor(gtk_native_get_surface(GTK_NATIVE(win)));
    printf("toplevel %dx%d, content at (%d,%d) %dx%d, pixel size %dx%d, scale %d\n",
           t.width, t.height, a.x, a.y, a.width, a.height, pw, ph, scale);
    // With a header bar on a server with no compositor, GTK frames the window in a border that
    // ionCreateWindow's size request does not count, so the client comes out smaller than asked.
    if (!header) check(a.width == 400 * scale && a.height == 300 * scale, "content is the requested 400x300 client area in device pixels");
    check(a.width == pw && a.height == ph, "content size equals ionWindowPixelWidth/Height");
    check(a.x >= 0 && a.y >= 0 && a.x + a.width <= t.width && a.y + a.height <= t.height, "content lies inside the toplevel");
    if (header) check(a.y > 0, "a client-side header bar sits above the content");
    check(a.your_event_mask == 0, "the content window selects no events on the probe connection");
    check(a.map_state != IsUnmapped, "the content window is mapped");

    GC gc = XCreateGC(dpy, (Window)xid, 0, NULL);
    XSetForeground(dpy, gc, 0xff0000);
    XFillRectangle(dpy, (Window)xid, gc, 0, 0, (unsigned)a.width, (unsigned)a.height);
    XSync(dpy, False);
    check(pixelAt(dpy, top, a.x + 3, a.y + 3) == 0xff0000, "a fill into the XID shows at the content origin of the toplevel");
    check(pixelAt(dpy, top, a.x + a.width - 3, a.y + a.height - 3) == 0xff0000, "and at its far corner");
    if (a.y > 0) check(pixelAt(dpy, top, a.x + 3, a.y - 2) != 0xff0000, "the header bar above it is not covered");

#ifdef ION_PROBE_VOID
    XErrorHandler gdkHandler = XSetErrorHandler(onXError);
    XSetErrorHandler(gdkHandler);
    voidLinuxViewsStart(1);
    VoidLinuxView view;
    voidLinuxViewInit(&view, (unsigned long)xid, a.width, a.height);
    XErrorHandler afterVoid = XSetErrorHandler(onXError);
    printf("INFO GDK's X error handler %s after voidLinuxViewInit\n", afterVoid == gdkHandler ? "kept" : "replaced");
    voidClear(&view);
    XSync(dpy, False);
    check(pixelAt(dpy, top, a.x + 3, a.y + 3) == 0x00ff00, "Void's clear shows at the content origin of the toplevel");
    check(pixelAt(dpy, top, a.x + a.width - 3, a.y + a.height - 3) == 0x00ff00, "and at its far corner");
    if (a.y > 0) check(pixelAt(dpy, top, a.x + 3, a.y - 2) != 0x00ff00, "Void does not cover the header bar");
#endif

    ionSetWindowSize(id, 520, 380);
    pump(800);
    geometry(dpy, (Window)xid, &a);
    printf("after resize: content at (%d,%d) %dx%d, pixel size %dx%d\n", a.x, a.y, a.width, a.height,
           ionWindowPixelWidth(id), ionWindowPixelHeight(id));
    if (!header) check(a.width == 520 * scale && a.height == 380 * scale, "content follows a resize to 520x380");
    check(a.width == ionWindowPixelWidth(id) && a.height == ionWindowPixelHeight(id), "and still equals the pixel size");

#ifdef ION_PROBE_VOID
    voidLinuxViewResize(&view, a.width, a.height);
    voidClear(&view);
    XSync(dpy, False);
    check(pixelAt(dpy, top, a.x + a.width - 3, a.y + a.height - 3) == 0x00ff00, "after viewResize Void fills the grown content");
    voidLinuxViewRelease(&view);
#endif

    ionCloseWindow(id);
    pump(300);
    s_xError = 0;
    geometry(dpy, (Window)xid, &a);
    check(s_xError == BadWindow, "closing the window destroys the XID");

    XFreeGC(dpy, gc);
    XCloseDisplay(dpy);
    printf("%s, %d failure(s)\n", s_failures ? "RED" : "GREEN", s_failures);
    return s_failures ? 1 : 0;
}
