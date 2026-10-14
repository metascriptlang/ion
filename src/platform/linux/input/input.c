// One process-wide GDK event hook turns each window's input into records before GTK
// dispatches it, so a webview still receives its own events. Key records are pushed only
// while no widget inside the window holds focus.


#include "../state.h"
#include "../internal.h"
#include "../../bridge.h"
#include "../../common/inputEvents.h"
#include "../../common/keys.h"
#include "../../common/utf16.h"

#include <gdk/gdk.h>
#include <gdk/gdkkeysyms.h>
#include <string.h>
#include <webkit2/webkit2.h>

static int s_installed = 0;
static unsigned char s_keyDown[256];
static int s_buttonsDown;

static int evdevToKey(unsigned sc) {
    static const unsigned char row1[] = {   // evdev 16..27 qwertyuiop[]
        ION_KEY_KEY_Q, ION_KEY_KEY_W, ION_KEY_KEY_E, ION_KEY_KEY_R, ION_KEY_KEY_T,
        ION_KEY_KEY_Y, ION_KEY_KEY_U, ION_KEY_KEY_I, ION_KEY_KEY_O, ION_KEY_KEY_P,
        ION_KEY_BRACKET_LEFT, ION_KEY_BRACKET_RIGHT };
    static const unsigned char row2[] = {   // evdev 30..40 asdfghjkl;'
        ION_KEY_KEY_A, ION_KEY_KEY_S, ION_KEY_KEY_D, ION_KEY_KEY_F, ION_KEY_KEY_G,
        ION_KEY_KEY_H, ION_KEY_KEY_J, ION_KEY_KEY_K, ION_KEY_KEY_L,
        ION_KEY_SEMICOLON, ION_KEY_QUOTE };
    static const unsigned char row3[] = {   // evdev 44..53 zxcvbnm,./
        ION_KEY_KEY_Z, ION_KEY_KEY_X, ION_KEY_KEY_C, ION_KEY_KEY_V, ION_KEY_KEY_B,
        ION_KEY_KEY_N, ION_KEY_KEY_M, ION_KEY_COMMA, ION_KEY_PERIOD, ION_KEY_SLASH };
    if (sc >= 2 && sc <= 10) return ION_KEY_DIGIT1 + (int)(sc - 2);
    if (sc >= 16 && sc <= 27) return row1[sc - 16];
    if (sc >= 30 && sc <= 40) return row2[sc - 30];
    if (sc >= 44 && sc <= 53) return row3[sc - 44];
    if (sc >= 59 && sc <= 68) return ION_KEY_F1 + (int)(sc - 59);
    if (sc >= 71 && sc <= 73) return ION_KEY_NUMPAD7 + (int)(sc - 71);
    if (sc >= 75 && sc <= 77) return ION_KEY_NUMPAD4 + (int)(sc - 75);
    if (sc >= 79 && sc <= 81) return ION_KEY_NUMPAD1 + (int)(sc - 79);
    switch (sc) {
        case 1: return ION_KEY_ESCAPE;
        case 11: return ION_KEY_DIGIT0;
        case 12: return ION_KEY_MINUS;
        case 13: return ION_KEY_EQUAL;
        case 14: return ION_KEY_BACKSPACE;
        case 15: return ION_KEY_TAB;
        case 28: return ION_KEY_ENTER;
        case 29: return ION_KEY_CONTROL_LEFT;
        case 41: return ION_KEY_BACKQUOTE;
        case 42: return ION_KEY_SHIFT_LEFT;
        case 43: return ION_KEY_BACKSLASH;
        case 54: return ION_KEY_SHIFT_RIGHT;
        case 55: return ION_KEY_NUMPAD_MULTIPLY;
        case 56: return ION_KEY_ALT_LEFT;
        case 57: return ION_KEY_SPACE;
        case 58: return ION_KEY_CAPS_LOCK;
        case 69: return ION_KEY_NUM_LOCK;
        case 70: return ION_KEY_SCROLL_LOCK;
        case 74: return ION_KEY_NUMPAD_SUBTRACT;
        case 78: return ION_KEY_NUMPAD_ADD;
        case 82: return ION_KEY_NUMPAD0;
        case 83: return ION_KEY_NUMPAD_DECIMAL;
        case 86: return ION_KEY_INTL_BACKSLASH;
        case 87: return ION_KEY_F11;
        case 88: return ION_KEY_F12;
        case 96: return ION_KEY_NUMPAD_ENTER;
        case 97: return ION_KEY_CONTROL_RIGHT;
        case 98: return ION_KEY_NUMPAD_DIVIDE;
        case 99: return ION_KEY_PRINT_SCREEN;
        case 100: return ION_KEY_ALT_RIGHT;
        case 102: return ION_KEY_HOME;
        case 103: return ION_KEY_ARROW_UP;
        case 104: return ION_KEY_PAGE_UP;
        case 105: return ION_KEY_ARROW_LEFT;
        case 106: return ION_KEY_ARROW_RIGHT;
        case 107: return ION_KEY_END;
        case 108: return ION_KEY_ARROW_DOWN;
        case 109: return ION_KEY_PAGE_DOWN;
        case 110: return ION_KEY_INSERT;
        case 111: return ION_KEY_DELETE;
        case 119: return ION_KEY_PAUSE;
        case 125: return ION_KEY_META_LEFT;
        case 126: return ION_KEY_META_RIGHT;
        case 127: return ION_KEY_CONTEXT_MENU;
        default: return ION_KEY_UNIDENTIFIED;
    }
}

static int modsFromState(guint state) {
    int m = 0;
    if (state & GDK_SHIFT_MASK)   m |= ION_MOD_SHIFT;
    if (state & GDK_CONTROL_MASK) m |= ION_MOD_CTRL;
    if (state & GDK_MOD1_MASK)    m |= ION_MOD_ALT;
    if (state & (GDK_SUPER_MASK | GDK_MOD4_MASK)) m |= ION_MOD_SUPER;
    if (state & GDK_LOCK_MASK)    m |= ION_MOD_CAPS_LOCK;
    if (state & GDK_MOD2_MASK)    m |= ION_MOD_NUM_LOCK;
    return m;
}

static int contentHasKeyboard(IonLinuxWindowState *st) {
    return gtk_window_is_active(GTK_WINDOW(st->window))
        && gtk_window_get_focus(GTK_WINDOW(st->window)) == NULL;
}

void ionLinuxUpdateContentFocus(IonLinuxWindowState *st) {
    int has = contentHasKeyboard(st);
    if (has == st->contentFocused) return;
    st->contentFocused = has;
    if (has) gtk_im_context_focus_in(st->im); else gtk_im_context_focus_out(st->im);
    IonInputRecord r;
    memset(&r, 0, sizeof r);
    r.type = ION_INPUT_FOCUS;
    r.window = st->id;
    r.p1 = has;
    ion_input_push_record(&r);
}

void ionLinuxPushResize(IonLinuxWindowState *st) {
    int scale = gtk_widget_get_scale_factor(st->root);
    int w = gtk_widget_get_allocated_width(st->root) * scale;
    int h = gtk_widget_get_allocated_height(st->root) * scale;
    if (w == st->clientW && h == st->clientH) return;
    st->clientW = w;
    st->clientH = h;
    IonInputRecord r;
    memset(&r, 0, sizeof r);
    r.type = ION_INPUT_RESIZE;
    r.window = st->id;
    r.x = scale;
    r.p1 = w;
    r.p2 = h;
    ion_input_push_record(&r);
}

static int clientPoint(IonLinuxWindowState *st, double xRoot, double yRoot,
                       double *px, double *py) {
    GdkWindow *gw = gtk_widget_get_window(st->window);
    if (!gw) return 0;
    gint ox = 0, oy = 0, dx = 0, dy = 0;
    gdk_window_get_origin(gw, &ox, &oy);
    gtk_widget_translate_coordinates(st->root, st->window, 0, 0, &dx, &dy);
    double scale = gtk_widget_get_scale_factor(st->root);
    double x = xRoot - ox - dx, y = yRoot - oy - dy;
    *px = x * scale;
    *py = y * scale;
    return x >= 0 && y >= 0
        && x < gtk_widget_get_allocated_width(st->root)
        && y < gtk_widget_get_allocated_height(st->root);
}

static int ionButton(guint gdkButton) {
    switch (gdkButton) {
        case 1: return 1;
        case 3: return 2;
        case 2: return 3;
        case 8: return 4;
        case 9: return 5;
        default: return 0;
    }
}

static void pushPointer(IonLinuxWindowState *st, int type, double x, double y,
                        double p1, double p2) {
    IonInputRecord r;
    memset(&r, 0, sizeof r);
    r.type = type;
    r.window = st->id;
    r.x = x;
    r.y = y;
    r.p1 = p1;
    r.p2 = p2;
    ion_input_push_record(&r);
}

static void onKey(IonLinuxWindowState *st, GdkEventKey *e) {
    int press = e->type == GDK_KEY_PRESS;
    int filtered = gtk_im_context_filter_keypress(st->im, e);
    unsigned hw = e->hardware_keycode;

    int kind = ION_KEY_RELEASE;
    if (press) kind = (hw < 256 && s_keyDown[hw]) ? ION_KEY_REPEAT : ION_KEY_PRESS;
    if (hw < 256) s_keyDown[hw] = press ? 1 : 0;

    GdkKeymap *km = gdk_keymap_get_for_display(gdk_window_get_display(e->window));
    GdkModifierType consumed = 0;
    guint unshiftedKeyval = 0;
    gdk_keymap_translate_keyboard_state(km, hw, 0, e->group, &unshiftedKeyval, NULL, NULL, NULL);
    guint effKeyval = 0;
    gdk_keymap_translate_keyboard_state(km, hw, (GdkModifierType)e->state, e->group,
                                        &effKeyval, NULL, NULL, &consumed);

    char text[8] = {0};
    gunichar ch = gdk_keyval_to_unicode(e->keyval);
    if (press && !filtered && ch >= 0x20 && ch != 0x7f
        && !(e->state & (GDK_CONTROL_MASK | GDK_MOD1_MASK | GDK_SUPER_MASK))) {
        g_unichar_to_utf8(ch, text);
    }

    IonInputRecord r;
    memset(&r, 0, sizeof r);
    r.type = ION_INPUT_KEY;
    r.window = st->id;
    r.p1 = kind;
    r.key = evdevToKey(hw >= 8 ? hw - 8 : 0);
    r.scancode = (int)hw;
    r.mods = modsFromState(e->state);
    r.consumedMods = modsFromState((guint)consumed);
    r.unshifted = gdk_keyval_to_unicode(unshiftedKeyval);
    r.text = text;
    ion_input_push_record(&r);
}

static void process(GdkEvent *ev) {
    GtkWidget *w = gtk_get_event_widget(ev);
    if (!w) return;
    IonLinuxWindowState *st = ionLinuxWindowForToplevel(gtk_widget_get_toplevel(w));
    if (!st) return;

    double px, py;
    switch (ev->type) {
        case GDK_BUTTON_PRESS: {
            int b = ionButton(ev->button.button);
            if (!b || !clientPoint(st, ev->button.x_root, ev->button.y_root, &px, &py)) return;
            s_buttonsDown |= 1 << b;
            pushPointer(st, ION_INPUT_BUTTON, px, py, b, 1);
            break;
        }
        case GDK_BUTTON_RELEASE: {
            int b = ionButton(ev->button.button);
            if (!b || !(s_buttonsDown & (1 << b))) return;
            s_buttonsDown &= ~(1 << b);
            clientPoint(st, ev->button.x_root, ev->button.y_root, &px, &py);
            pushPointer(st, ION_INPUT_BUTTON, px, py, b, 0);
            break;
        }
        case GDK_MOTION_NOTIFY: {
            int inside = clientPoint(st, ev->motion.x_root, ev->motion.y_root, &px, &py);
            if (!inside && !s_buttonsDown) return;
            double dx = st->pointerKnown ? px - st->lastX : 0;
            double dy = st->pointerKnown ? py - st->lastY : 0;
            st->pointerKnown = 1;
            st->lastX = px;
            st->lastY = py;
            pushPointer(st, ION_INPUT_MOTION, px, py, dx, dy);
            break;
        }
        case GDK_SCROLL: {
            double dx = 0, dy = 0;
            switch (ev->scroll.direction) {
                case GDK_SCROLL_UP:     dy = 1; break;
                case GDK_SCROLL_DOWN:   dy = -1; break;
                case GDK_SCROLL_LEFT:   dx = -1; break;
                case GDK_SCROLL_RIGHT:  dx = 1; break;
                case GDK_SCROLL_SMOOTH: dx = ev->scroll.delta_x; dy = -ev->scroll.delta_y; break;
                default: return;
            }
            if (!clientPoint(st, ev->scroll.x_root, ev->scroll.y_root, &px, &py)) return;
            pushPointer(st, ION_INPUT_WHEEL, px, py, dx, dy);
            break;
        }
        case GDK_LEAVE_NOTIFY:
            if (ev->crossing.window != gtk_widget_get_window(st->window)
             || ev->crossing.detail == GDK_NOTIFY_INFERIOR
             || ev->crossing.mode != GDK_CROSSING_NORMAL) return;
            st->pointerKnown = 0;
            pushPointer(st, ION_INPUT_LEAVE, 0, 0, 0, 0);
            break;
        case GDK_KEY_PRESS:
        case GDK_KEY_RELEASE:
            if (contentHasKeyboard(st)) onKey(st, &ev->key);
            break;
        default:
            break;
    }
}

static void onGdkEvent(GdkEvent *ev, gpointer data) {
    (void)data;
    process(ev);
    gtk_main_do_event(ev);
}

void ionLinuxInstallInput(void) {
    if (s_installed) return;
    s_installed = 1;
    gdk_event_handler_set(onGdkEvent, NULL, NULL);
}

static void onCommit(GtkIMContext *im, gchar *str, gpointer data) {
    (void)im;
    IonLinuxWindowState *st = (IonLinuxWindowState *)data;
    IonInputRecord r;
    memset(&r, 0, sizeof r);
    r.type = ION_INPUT_TEXT;
    r.window = st->id;
    r.text = str;
    ion_input_push_record(&r);
}

static void onPreeditChanged(GtkIMContext *im, gpointer data) {
    IonLinuxWindowState *st = (IonLinuxWindowState *)data;
    gchar *str = NULL;
    gint cursor = 0;
    gtk_im_context_get_preedit_string(im, &str, NULL, &cursor);
    IonInputRecord r;
    memset(&r, 0, sizeof r);
    r.type = ION_INPUT_PREEDIT;
    r.window = st->id;
    r.text = str ? str : "";
    r.p1 = str ? (double)ion_utf16_units(str, cursor) : 0;
    ion_input_push_record(&r);
    g_free(str);
}

static void onRealize(GtkWidget *w, gpointer data) {
    IonLinuxWindowState *st = (IonLinuxWindowState *)data;
    gtk_im_context_set_client_window(st->im, gtk_widget_get_window(w));
}

void ionLinuxAttachInput(IonLinuxWindowState *st) {
    st->im = gtk_im_multicontext_new();
    g_signal_connect(st->im, "commit", G_CALLBACK(onCommit), st);
    g_signal_connect(st->im, "preedit-changed", G_CALLBACK(onPreeditChanged), st);
    g_signal_connect(st->window, "realize", G_CALLBACK(onRealize), st);
}

void ionLinuxDetachInput(IonLinuxWindowState *st) {
    gtk_im_context_set_client_window(st->im, NULL);
    g_signal_handlers_disconnect_by_data(st->im, st);
    g_object_unref(st->im);
    st->im = NULL;
}

void ionWindowSetImeRect(IonWindowId id, int x, int y, int w, int h) {
    IonLinuxWindowState *st = ionLinuxWindowState(id);
    if (!st) return;
    int scale = gtk_widget_get_scale_factor(st->root);
    GdkRectangle r = { x / scale, y / scale, w / scale, h / scale };
    gtk_im_context_set_cursor_location(st->im, &r);
}
