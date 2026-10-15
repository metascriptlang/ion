// Global hotkeys exist only on an X11 GDK display (XGrabKey on a second X connection that
// a GSource watches: GDK4 has no event filter). On Wayland no client can grab a key
// globally; registration prints the limit and returns -1.

#include "../state.h"
#include "../internal.h"
#include "../../bridge.h"
#include "../../common/queue.h"

#include <X11/Xlib.h>
#include <gdk/x11/gdkx.h>
#include <glib-unix.h>
#include <gtk/gtk.h>
#include <stdio.h>

typedef struct {
    int           id;
    KeyCode       keyCode;
    unsigned int  modMask;
} IonHotkey;

static IonHotkey s_hotkeys[16];
static int       s_hotkeyCount = 0;
static Display  *s_dpy         = NULL;

#define ION_RELEVANT_MODS (ShiftMask | ControlMask | Mod1Mask | Mod4Mask)
static const unsigned int kLockCombos[] = { 0, LockMask, Mod2Mask, LockMask | Mod2Mask };

static gboolean onX11Ready(gint fd, GIOCondition cond, gpointer data) {
    (void)fd; (void)cond; (void)data;
    while (XPending(s_dpy)) {
        XEvent ev;
        XNextEvent(s_dpy, &ev);
        if (ev.type != KeyPress) continue;
        unsigned int mods = ev.xkey.state & ION_RELEVANT_MODS;
        for (int i = 0; i < s_hotkeyCount; i++) {
            if (s_hotkeys[i].keyCode == (KeyCode)ev.xkey.keycode && s_hotkeys[i].modMask == mods) {
                char buf[16];
                snprintf(buf, sizeof(buf), "%d", s_hotkeys[i].id);
                ion_queue_push("hotkey", buf);
                ionLinuxPresentMain();
                break;
            }
        }
    }
    return G_SOURCE_CONTINUE;
}

static int ensureX11(void) {
    if (s_dpy != NULL) return 1;
    GdkDisplay *gdkDisp = gdk_display_get_default();
    if (gdkDisp == NULL || !GDK_IS_X11_DISPLAY(gdkDisp)) {
        fprintf(stderr, "[ion] registerHotkey: unavailable on Wayland, a client cannot grab a key globally; "
                        "rerun with GDK_BACKEND=x11\n");
        return 0;
    }
    s_dpy = XOpenDisplay(gdk_display_get_name(gdkDisp));
    if (s_dpy == NULL) {
        fprintf(stderr, "[ion] registerHotkey: XOpenDisplay failed\n");
        return 0;
    }
    g_unix_fd_add(ConnectionNumber(s_dpy), G_IO_IN, onX11Ready, NULL);
    return 1;
}

int ionRegisterHotkey(int modifiers, int keyCode, int id) {
    if (s_hotkeyCount >= (int)(sizeof(s_hotkeys) / sizeof(s_hotkeys[0]))) return 0;
    if (!ensureX11()) return -1;

    unsigned int mask = 0;
    if (modifiers & 1) mask |= ControlMask;
    if (modifiers & 2) mask |= ShiftMask;
    if (modifiers & 4) mask |= Mod1Mask;
    if (modifiers & 8) mask |= ControlMask;

    KeyCode kc = XKeysymToKeycode(s_dpy, (KeySym)keyCode);
    if (kc == 0) return -1;

    Window root = DefaultRootWindow(s_dpy);
    for (size_t i = 0; i < sizeof(kLockCombos) / sizeof(kLockCombos[0]); i++) {
        XGrabKey(s_dpy, kc, mask | kLockCombos[i], root, True, GrabModeAsync, GrabModeAsync);
    }
    XSync(s_dpy, False);

    s_hotkeys[s_hotkeyCount].id      = id;
    s_hotkeys[s_hotkeyCount].keyCode = kc;
    s_hotkeys[s_hotkeyCount].modMask = mask;
    s_hotkeyCount++;
    return 1;
}

void ionUnregisterHotkey(int id) {
    for (int i = 0; i < s_hotkeyCount; i++) {
        if (s_hotkeys[i].id != id) continue;
        Window root = DefaultRootWindow(s_dpy);
        for (size_t c = 0; c < sizeof(kLockCombos) / sizeof(kLockCombos[0]); c++) {
            XUngrabKey(s_dpy, s_hotkeys[i].keyCode, s_hotkeys[i].modMask | kLockCombos[c], root);
        }
        XSync(s_dpy, False);
        s_hotkeys[i] = s_hotkeys[--s_hotkeyCount];
        return;
    }
}
