#include "../internal.h"

#include <gdk/x11/gdkx.h>
#include <X11/Xlib.h>
#include <math.h>

// gdk_x11_*_get_xid and get_xdisplay are deprecated since GTK 4.18 with no replacement.
G_GNUC_BEGIN_IGNORE_DEPRECATIONS
int ionLinuxX11SetAbove(GtkWidget *window, int on) {
    GdkSurface *surface = gtk_native_get_surface(GTK_NATIVE(window));
    if (surface == NULL || !GDK_IS_X11_SURFACE(surface)) return 0;
    Display *dpy = gdk_x11_display_get_xdisplay(gdk_surface_get_display(surface));

    XEvent e = {0};
    e.xclient.type = ClientMessage;
    e.xclient.window = gdk_x11_surface_get_xid(surface);
    e.xclient.message_type = XInternAtom(dpy, "_NET_WM_STATE", False);
    e.xclient.format = 32;
    e.xclient.data.l[0] = on ? 1 : 0;
    e.xclient.data.l[1] = (long)XInternAtom(dpy, "_NET_WM_STATE_ABOVE", False);
    e.xclient.data.l[3] = 1;
    XSendEvent(dpy, DefaultRootWindow(dpy), False,
               SubstructureRedirectMask | SubstructureNotifyMask, &e);
    XFlush(dpy);
    return 1;
}

int ionLinuxX11Display(void) {
    GdkDisplay *display = gdk_display_get_default();
    return display != NULL && GDK_IS_X11_DISPLAY(display);
}

static Display *xDisplayOf(GtkWidget *window) {
    return gdk_x11_display_get_xdisplay(gtk_widget_get_display(window));
}

unsigned long ionLinuxX11CreateContent(GtkWidget *window) {
    if (!GDK_IS_X11_DISPLAY(gtk_widget_get_display(window))) return 0;
    gtk_widget_realize(window);
    GdkSurface *surface = gtk_native_get_surface(GTK_NATIVE(window));
    if (surface == NULL) return 0;
    Display *dpy = xDisplayOf(window);
    XSetWindowAttributes none = {0};
    Window xid = XCreateWindow(dpy, gdk_x11_surface_get_xid(surface), 0, 0, 1, 1, 0, CopyFromParent,
                               InputOutput, CopyFromParent, 0, &none);
    XMapWindow(dpy, xid);
    XFlush(dpy);
    return xid;
}

void ionLinuxX11PlaceContent(GtkWidget *window, unsigned long xid, GtkWidget *content) {
    GdkSurface *surface = gtk_native_get_surface(GTK_NATIVE(window));
    graphene_point_t at;
    if (xid == 0 || surface == NULL ||
        !gtk_widget_compute_point(content, window, &GRAPHENE_POINT_INIT(0, 0), &at)) return;
    double shadowX, shadowY;
    gtk_native_get_surface_transform(GTK_NATIVE(window), &shadowX, &shadowY);
    double scale = gdk_surface_get_scale(surface);
    long w = lround(gtk_widget_get_width(content) * scale), h = lround(gtk_widget_get_height(content) * scale);
    Display *dpy = xDisplayOf(window);
    XMoveResizeWindow(dpy, xid, (int)lround((at.x + shadowX) * scale), (int)lround((at.y + shadowY) * scale),
                      (unsigned)(w > 0 ? w : 1), (unsigned)(h > 0 ? h : 1));
    XFlush(dpy);
}

void ionLinuxX11DestroyContent(GtkWidget *window, unsigned long xid) {
    if (xid == 0) return;
    Display *dpy = xDisplayOf(window);
    XDestroyWindow(dpy, xid);
    XFlush(dpy);
}
G_GNUC_END_IGNORE_DEPRECATIONS
