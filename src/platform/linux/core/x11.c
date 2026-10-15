#include "../internal.h"

#include <gdk/x11/gdkx.h>
#include <X11/Xlib.h>

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
G_GNUC_END_IGNORE_DEPRECATIONS
