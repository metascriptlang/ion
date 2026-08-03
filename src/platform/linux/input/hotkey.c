// Ion Linux — global hotkey via XGrabKey + GDK X11 event filter.
//
// XGrabKey installs a system-wide passive grab on the X server's root
// window — once registered, our process receives the key press regardless
// of which top-level has focus. Carbon RegisterEventHotKey (mac) and Win32
// RegisterHotKey are the analogues; same contract from MS-side.
//
// Platform constraint: X11 sessions and Wayland-via-XWayland both work
// because gdk_x11_display_get_xdisplay gives us an X11 Display* either
// way. Under pure Wayland (no XWayland), `GDK_IS_X11_DISPLAY` returns
// FALSE → we refuse with -1, matching Carbon's "OS refused" path. The
// portable alternative is `org.freedesktop.portal.GlobalShortcuts` (GNOME
// 45+, KDE 6+) — deferred, most MyApp target distros default to X11
// or X11+XWayland.
//
// Slot table fixed at 16, mirroring macOS. Hit → "hotkey" IPC with payload
// = id (decimal string).
//
// MS-side passes `keyCode` as an X11 KeySym (e.g. XK_l = 0x6c). We convert
// to the display-specific keycode via XKeysymToKeycode at registration —
// this isolates the MS side from per-display scancode tables.

#include "../state.h"
#include "../../bridge.h"
#include "../../common/queue.h"

#include <X11/Xlib.h>
#include <X11/keysym.h>
#include <gdk/gdk.h>
#include <gdk/gdkx.h>
#include <gtk/gtk.h>
#include <stdio.h>

typedef struct {
    int           id;
    KeyCode       keyCode;   // resolved display-specific scancode
    unsigned int  modMask;   // X11 modifier mask (ShiftMask, Mod1Mask, Mod4Mask, ControlMask)
} IonHotkey;

static IonHotkey s_hotkeys[16];
static int       s_hotkeyCount   = 0;
static Display  *s_x11Display    = NULL;
static int       s_filterHooked  = 0;

// Pre-built mask of bits we honor — caps/num/scroll-lock bits are stripped
// from incoming events so they don't break matching when lock keys are toggled.
#define ION_RELEVANT_MODS (ShiftMask | ControlMask | Mod1Mask | Mod4Mask)

static GdkFilterReturn keyEventFilter(GdkXEvent *xevent, GdkEvent *event, gpointer data) {
    (void)event; (void)data;
    XEvent *xev = (XEvent *)xevent;
    if (xev->type != KeyPress) return GDK_FILTER_CONTINUE;

    unsigned int incomingMods = xev->xkey.state & ION_RELEVANT_MODS;
    KeyCode      incomingKey  = (KeyCode)xev->xkey.keycode;

    for (int i = 0; i < s_hotkeyCount; i++) {
        if (s_hotkeys[i].keyCode == incomingKey
         && s_hotkeys[i].modMask == incomingMods) {
            char buf[16];
            snprintf(buf, sizeof(buf), "%d", s_hotkeys[i].id);
            ion_queue_push("hotkey", buf);
            if (s_mainWindow != NULL) {
                gtk_window_present(GTK_WINDOW(s_mainWindow));
            }
            // Consume — don't let the key event propagate further. Matches
            // Carbon's exclusive grab semantics.
            return GDK_FILTER_REMOVE;
        }
    }
    return GDK_FILTER_CONTINUE;
}

// Acquire the X11 Display* if the current GDK session has one (X11 or
// XWayland). Returns 1 on success, 0 on pure-Wayland (no XGrabKey path).
static int ensureX11Hooked(void) {
    if (s_filterHooked) return 1;

    GdkDisplay *gdkDisp = gdk_display_get_default();
    if (gdkDisp == NULL || !GDK_IS_X11_DISPLAY(gdkDisp)) {
        // Pure-Wayland session — XGrabKey path unavailable. Hint at the
        // GDK_BACKEND=x11 workaround so dev users aren't left guessing
        // why global hotkeys don't fire on their Wayland desktop.
        fprintf(stderr, "[ion] hotkey unavailable: GTK is on Wayland — "
                        "rerun with GDK_BACKEND=x11 to enable XGrabKey, "
                        "or wait for portal-based hotkeys.\n");
        return 0;
    }
    s_x11Display = gdk_x11_display_get_xdisplay(gdkDisp);
    if (s_x11Display == NULL) return 0;

    GdkWindow *root = gdk_get_default_root_window();
    gdk_window_add_filter(root, keyEventFilter, NULL);
    s_filterHooked = 1;
    return 1;
}

int ionRegisterHotkey(int modifiers, int keyCode, int id) {
    if (s_hotkeyCount >= (int)(sizeof(s_hotkeys) / sizeof(s_hotkeys[0]))) return 0;
    if (!ensureX11Hooked()) return -1;

    // ion bitmask: 1=Cmd, 2=Shift, 4=Alt, 8=Ctrl. On Linux + Windows the
    // "Cmd" abstraction maps to Ctrl (Tauri's `CmdOrCtrl` convention —
    // Ctrl+C is copy across non-Mac OSes, matching user muscle memory). If
    // a caller explicitly wants Super/Mod4, expose a separate ModSuper bit
    // — currently unused by helloWebview, can extend mods.ms when needed.
    unsigned int mask = 0;
    if (modifiers & 1) mask |= ControlMask;  // Cmd → Ctrl on Linux
    if (modifiers & 2) mask |= ShiftMask;
    if (modifiers & 4) mask |= Mod1Mask;     // Alt
    if (modifiers & 8) mask |= ControlMask;  // explicit Ctrl (idempotent if Cmd also set)

    KeyCode kc = XKeysymToKeycode(s_x11Display, (KeySym)keyCode);
    if (kc == 0) return -1;

    Window root = DefaultRootWindow(s_x11Display);
    // GrabModeAsync — don't freeze keyboard waiting on us to ack. XGrabKey
    // doesn't return a status; BadAccess (combo already grabbed) arrives
    // async via the X error handler. For v0 we trust the server — the
    // filter simply won't fire if another app owns the combo.
    XGrabKey(s_x11Display, kc, mask, root, True, GrabModeAsync, GrabModeAsync);
    XSync(s_x11Display, False);

    s_hotkeys[s_hotkeyCount].id      = id;
    s_hotkeys[s_hotkeyCount].keyCode = kc;
    s_hotkeys[s_hotkeyCount].modMask = mask;
    s_hotkeyCount++;
    return 1;
}

void ionUnregisterHotkey(int id) {
    for (int i = 0; i < s_hotkeyCount; i++) {
        if (s_hotkeys[i].id == id) {
            if (s_x11Display != NULL) {
                Window root = DefaultRootWindow(s_x11Display);
                XUngrabKey(s_x11Display, s_hotkeys[i].keyCode, s_hotkeys[i].modMask, root);
                XSync(s_x11Display, False);
            }
            s_hotkeys[i] = s_hotkeys[--s_hotkeyCount];
            return;
        }
    }
}
