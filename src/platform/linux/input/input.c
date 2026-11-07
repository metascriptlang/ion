// A capture-phase legacy controller on each window turns its input into records before
// the targeted widget, so a webview still receives its own events. Key records are
// pushed only while no widget inside the window holds focus.

#include "../state.h"
#include "../internal.h"
#include "../../bridge.h"
#include "../../common/inputEvents.h"
#include "../../common/keys.h"
#include "../../common/utf16.h"

#include <gdk/gdk.h>
#include <math.h>
#include <string.h>


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
    if (state & GDK_ALT_MASK)     m |= ION_MOD_ALT;
    if (state & GDK_SUPER_MASK)   m |= ION_MOD_SUPER;
    if (state & GDK_LOCK_MASK)    m |= ION_MOD_CAPS_LOCK;
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

void ionLinuxPushResize(IonLinuxWindowState *st, int logicalW, int logicalH) {
    double scale = ionLinuxScale(st);
    int w = (int)lround(logicalW * scale);
    int h = (int)lround(logicalH * scale);
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

// Event positions are in surface coordinates; the root sits below the titlebar.
static int clientPoint(IonLinuxWindowState *st, GdkEvent *ev, double *px, double *py) {
    double sx, sy, ox = 0, oy = 0;
    if (!gdk_event_get_position(ev, &sx, &sy)) return 0;
    gtk_native_get_surface_transform(GTK_NATIVE(st->window), &ox, &oy);
    graphene_point_t in = GRAPHENE_POINT_INIT((float)(sx - ox), (float)(sy - oy));
    graphene_point_t out;
    if (!gtk_widget_compute_point(st->window, st->root, &in, &out)) return 0;
    double scale = ionLinuxScale(st);
    *px = out.x * scale;
    *py = out.y * scale;
    return out.x >= 0 && out.y >= 0
        && out.x < gtk_widget_get_width(st->root)
        && out.y < gtk_widget_get_height(st->root);
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

static void pushPointer(IonLinuxWindowState *st, int type, GtkEventController *controller,
                        double x, double y, double p1, double p2, int wheelUnit) {
    IonInputRecord r;
    memset(&r, 0, sizeof r);
    r.type = type;
    r.window = st->id;
    r.x = x;
    r.y = y;
    r.p1 = p1;
    r.p2 = p2;
    r.key = wheelUnit;
    r.mods = modsFromState(gtk_event_controller_get_current_event_state(controller));
    ion_input_push_record(&r);
}

static void pushLeave(IonLinuxWindowState *st, GtkEventController *controller) {
    if (!st->pointerKnown) return;
    st->pointerKnown = 0;
    pushPointer(st, ION_INPUT_LEAVE, controller, 0, 0, 0, 0, 0);
}

// xkb_keysym_to_utf8 (libxkbcommon keysym-utf.c): the keypad and the control keysyms carry
// their ASCII byte, which gdk_keyval_to_unicode leaves out for some of them.
static gunichar keyvalChar(guint keyval) {
    if ((keyval >= GDK_KEY_BackSpace && keyval <= GDK_KEY_Clear)
        || (keyval >= GDK_KEY_KP_Multiply && keyval <= GDK_KEY_KP_9)
        || keyval == GDK_KEY_Return || keyval == GDK_KEY_Escape || keyval == GDK_KEY_Delete
        || keyval == GDK_KEY_KP_Tab || keyval == GDK_KEY_KP_Enter || keyval == GDK_KEY_KP_Equal)
        return keyval & 0x7f;
    if (keyval == GDK_KEY_KP_Space) return ' ';
    return gdk_keyval_to_unicode(keyval);
}

// The last press pushed for a keycode: 0 none seen, PRESS_PASSED, PRESS_IME (imeHandled).
enum { PRESS_PASSED = 1, PRESS_IME = 2 };
static unsigned char s_lastPress[256];

typedef struct {
    IonInputRecord r;
    char text[64], chordText[8], allModsText[8];
} KeyRecord;

// The key's own character: what an IM that passes the key through commits for it.
static void ownChar(GdkEvent *ev, char out[8]) {
    gunichar ch = gdk_keyval_to_unicode(gdk_key_event_get_keyval(ev));
    memset(out, 0, 8);
    if (ch >= 0x20 && ch != 0x7f) g_unichar_to_utf8(ch, out);
}

static void buildKey(IonLinuxWindowState *st, GdkEvent *ev, int kind, int filtered,
                     const char *commit, KeyRecord *k) {
    int press = kind != ION_KEY_RELEASE;
    unsigned hw = gdk_key_event_get_keycode(ev);
    GdkModifierType state = gdk_event_get_modifier_state(ev);
    guint unshiftedKeyval = 0;
    gdk_display_translate_key(gdk_event_get_display(ev), hw, 0, gdk_key_event_get_layout(ev),
                              &unshiftedKeyval, NULL, NULL, NULL);

    memset(k, 0, sizeof *k);
    gunichar ch = gdk_keyval_to_unicode(gdk_key_event_get_keyval(ev));
    if (commit && commit[0]) {
        g_strlcpy(k->text, commit, sizeof k->text);
    } else if (press && !filtered && ch >= 0x20 && ch != 0x7f
        && !(state & (GDK_CONTROL_MASK | GDK_ALT_MASK | GDK_SUPER_MASK))) {
        g_unichar_to_utf8(ch, k->text);
    }

    k->r.type = ION_INPUT_KEY;
    k->r.window = st->id;
    k->r.p1 = kind;
    k->r.key = evdevToKey(hw >= 8 ? hw - 8 : 0);
    k->r.scancode = (int)hw;
    k->r.mods = modsFromState(state);
    k->r.consumedMods = modsFromState(gdk_key_event_get_consumed_modifiers(ev));
    k->r.unshifted = gdk_keyval_to_unicode(unshiftedKeyval);
    k->r.text = k->text;

    // winit's xkb KeyContext: text is the keysym's character, text_with_all_modifiers
    // applies Control as xkb_state_key_get_utf8 does when Control is active and not consumed.
    gunichar chord = filtered ? 0 : keyvalChar(gdk_key_event_get_keyval(ev));
    gunichar all = chord;
    if ((state & GDK_CONTROL_MASK) && !(gdk_key_event_get_consumed_modifiers(ev) & GDK_CONTROL_MASK))
        all = ionKeyCtrlChar(all);
    if (press && chord != 0) g_unichar_to_utf8(chord, k->chordText);
    if (all != 0) g_unichar_to_utf8(all, k->allModsText);
    k->r.chordText = k->chordText;
    k->r.allModsText = k->allModsText;
    k->r.imeHandled = filtered;
}

// An asynchronous IM answers for a press after filter_keypress returned TRUE, so the press is
// held (ION_IME_ANSWER_TIMEOUT_MS in bridge.h) and every later key, text and preedit record of
// its window waits behind it. passed is the record the press gets when the IM lets it through;
// the records the IM's answer produces go after the press (last), in the order macOS gives.
typedef struct QueuedRecord {
    IonInputRecord r;
    int held;
    gint64 deadline;
    GdkEvent *event;
    char own[8];
    KeyRecord passed;
    struct QueuedRecord *release;
    GList *link, *last;
} QueuedRecord;

static void setRecord(QueuedRecord *q, const IonInputRecord *r) {
    g_free((char *)q->r.text);
    g_free((char *)q->r.chordText);
    g_free((char *)q->r.allModsText);
    q->r = *r;
    q->r.text = g_strdup(r->text);
    q->r.chordText = g_strdup(r->chordText);
    q->r.allModsText = g_strdup(r->allModsText);
}

static void freeQueued(QueuedRecord *q) {
    IonInputRecord none = {0};
    setRecord(q, &none);
    if (q->event) gdk_event_unref(q->event);
    g_free(q);
}

static void pushNow(const IonInputRecord *r) {
    if (r->type == ION_INPUT_KEY && r->p1 != ION_KEY_RELEASE && r->scancode < 256)
        s_lastPress[r->scancode] = r->imeHandled ? PRESS_IME : PRESS_PASSED;
    ion_input_push_record(r);
}

static QueuedRecord *newQueued(const IonInputRecord *r) {
    QueuedRecord *q = g_new0(QueuedRecord, 1);
    setRecord(q, r);
    return q;
}

static QueuedRecord *queueRecord(IonLinuxWindowState *st, const IonInputRecord *r) {
    QueuedRecord *q = newQueued(r);
    g_queue_push_tail(&st->keyQueue, q);
    q->link = q->last = st->keyQueue.tail;
    return q;
}

static QueuedRecord *oldestHeld(IonLinuxWindowState *st) {
    for (GList *l = st->keyQueue.head; l; l = l->next)
        if (((QueuedRecord *)l->data)->held) return l->data;
    return NULL;
}

static void emit(IonLinuxWindowState *st, const IonInputRecord *r) {
    if (g_queue_is_empty(&st->keyQueue)) pushNow(r);
    else queueRecord(st, r);
}

// A record of the IM's own (a preedit, a commit no press is waiting for) goes before the
// oldest press still waiting, since the IM answers presses in order.
static void emitFromIm(IonLinuxWindowState *st, const IonInputRecord *r) {
    QueuedRecord *q = oldestHeld(st);
    if (!q) { emit(st, r); return; }
    g_queue_insert_before(&st->keyQueue, q->link, newQueued(r));
}

static void emitAfter(IonLinuxWindowState *st, QueuedRecord *q, const IonInputRecord *r) {
    g_queue_insert_after(&st->keyQueue, q->last, newQueued(r));
    q->last = q->last->next;
}

static void flushKeyQueue(IonLinuxWindowState *st) {
    QueuedRecord *q;
    while ((q = g_queue_peek_head(&st->keyQueue)) && !q->held) {
        g_queue_pop_head(&st->keyQueue);
        pushNow(&q->r);
        freeQueued(q);
    }
}

static QueuedRecord *heldFor(IonLinuxWindowState *st, GdkEvent *ev) {
    for (GList *l = st->keyQueue.head; l; l = l->next) {
        QueuedRecord *q = l->data;
        if (q->held && q->event == ev) return q;
    }
    return NULL;
}

// passed NULL: the IM took the press, which stays imeHandled.
static void answer(QueuedRecord *q, const KeyRecord *passed) {
    q->held = 0;
    if (passed) setRecord(q, &passed->r);
    if (q->release) q->release->r.imeHandled = q->r.imeHandled;
}

static gboolean onAnswerTimeout(gpointer data);

static void armAnswerTimer(IonLinuxWindowState *st) {
    QueuedRecord *q = oldestHeld(st);
    if (st->keyQueueTimer || !q) return;
    gint64 left = (q->deadline - g_get_monotonic_time() + 999) / 1000;
    st->keyQueueTimer = g_timeout_add(left > 0 ? (guint)left : 0, onAnswerTimeout, st);
}

static gboolean onAnswerTimeout(gpointer data) {
    IonLinuxWindowState *st = (IonLinuxWindowState *)data;
    st->keyQueueTimer = 0;
    gint64 now = g_get_monotonic_time();
    for (GList *l = st->keyQueue.head; l; l = l->next) {
        QueuedRecord *q = l->data;
        if (q->held && q->deadline <= now) answer(q, NULL);
    }
    flushKeyQueue(st);
    armAnswerTimer(st);
    return G_SOURCE_REMOVE;
}

// fcitx5-gtk puts an event it did not handle back on the display (gdk_display_put_event), and
// the controller sees that same GdkEvent a second time.
static void awaitEvent(IonLinuxWindowState *st, GdkEvent *ev) {
    GdkEvent **slot = &st->imAwaited[st->imAwaitedNext];
    if (*slot) gdk_event_unref(*slot);
    *slot = gdk_event_ref(ev);
    st->imAwaitedNext = (st->imAwaitedNext + 1) % (int)G_N_ELEMENTS(st->imAwaited);
}

static int takeAwaited(IonLinuxWindowState *st, GdkEvent *ev) {
    for (size_t i = 0; i < G_N_ELEMENTS(st->imAwaited); i++) {
        if (st->imAwaited[i] != ev) continue;
        gdk_event_unref(ev);
        st->imAwaited[i] = NULL;
        return 1;
    }
    return 0;
}

// Commits the IM fires inside filter_keypress are collected here; the caller decides whether
// they are the key's own text.
static IonLinuxWindowState *s_filterWindow;
static QueuedRecord *s_answering;
static GString *s_filterCommit;
static int s_filterPreedit;   // the IM changed its preedit inside filter_keypress

static int filterKey(IonLinuxWindowState *st, GdkEvent *ev) {
    if (!s_filterCommit) s_filterCommit = g_string_new(NULL);
    g_string_truncate(s_filterCommit, 0);
    s_filterPreedit = 0;
    s_filterWindow = st;
    int filtered = gtk_im_context_filter_keypress(st->im, ev);
    s_filterWindow = NULL;
    return filtered;
}

static void textRecord(IonLinuxWindowState *st, const char *text, IonInputRecord *r) {
    memset(r, 0, sizeof *r);
    r->type = ION_INPUT_TEXT;
    r->window = st->id;
    r->text = text;
}

// As macOS keyDown: a commit of exactly the key's own character with nothing composed is the
// key's text; any other commit makes the key imeHandled and follows it as a text record,
// which is returned.
static const char *settlePress(IonLinuxWindowState *st, GdkEvent *ev, int kind, int filtered,
                               int wasComposing, KeyRecord *k) {
    char own[8];
    ownChar(ev, own);
    const char *c = s_filterCommit->str;
    if (c[0] && !wasComposing && !st->imComposing && strcmp(c, own) == 0) {
        buildKey(st, ev, kind, 0, c, k);
        return NULL;
    }
    buildKey(st, ev, kind, filtered || c[0], NULL, k);
    return c[0] ? c : NULL;
}

// The re-delivered event goes through the IM once more, which now answers synchronously.
static void onRedelivered(IonLinuxWindowState *st, GdkEvent *ev) {
    QueuedRecord *q = heldFor(st, ev);
    int wasComposing = st->imComposing;
    s_answering = q;
    int filtered = filterKey(st, ev);
    s_answering = NULL;
    IonInputRecord t;
    if (!q) {
        textRecord(st, s_filterCommit->str, &t);
        if (t.text[0]) emitFromIm(st, &t);
        flushKeyQueue(st);
        return;
    }
    KeyRecord k;
    const char *other = settlePress(st, ev, (int)q->r.p1, filtered, wasComposing, &k);
    answer(q, &k);
    if (other) {
        textRecord(st, other, &t);
        emitAfter(st, q, &t);
    }
    flushKeyQueue(st);
}

static QueuedRecord *queuedPress(IonLinuxWindowState *st, int scancode) {
    for (GList *l = st->keyQueue.tail; l; l = l->prev) {
        QueuedRecord *q = l->data;
        if (q->r.type == ION_INPUT_KEY && q->r.p1 != ION_KEY_RELEASE && q->r.scancode == scancode) return q;
    }
    return NULL;
}

static void onKey(IonLinuxWindowState *st, GdkEvent *ev) {
    int press = gdk_event_get_event_type(ev) == GDK_KEY_PRESS;
    if (takeAwaited(st, ev)) {
        onRedelivered(st, ev);
        return;
    }
    int wasComposing = st->imComposing;
    int filtered = filterKey(st, ev);
    unsigned hw = gdk_key_event_get_keycode(ev);

    int kind = ION_KEY_RELEASE;
    if (press) kind = (hw < 256 && s_keyDown[hw]) ? ION_KEY_REPEAT : ION_KEY_PRESS;
    if (hw < 256) s_keyDown[hw] = press ? 1 : 0;

    KeyRecord k;
    IonInputRecord t;
    if (!press) {
        // A release is imeHandled when its press was, as macOS keyUp does.
        buildKey(st, ev, kind, filtered, NULL, &k);
        QueuedRecord *p = queuedPress(st, (int)hw);
        int last = hw < 256 ? s_lastPress[hw] : 0;
        k.r.imeHandled = p ? p->held || p->r.imeHandled : last ? last == PRESS_IME : filtered;
        if (filtered) awaitEvent(st, ev);
        if (p) p->release = queueRecord(st, &k.r);
        else emit(st, &k.r);
        textRecord(st, s_filterCommit->str, &t);
        if (t.text[0]) emit(st, &t);
        return;
    }
    const char *other = settlePress(st, ev, kind, filtered, wasComposing, &k);
    if (other || !k.r.imeHandled || s_filterPreedit) {
        emit(st, &k.r);
        if (other) {
            textRecord(st, other, &t);
            emit(st, &t);
        }
        return;
    }
    QueuedRecord *q = queueRecord(st, &k.r);
    q->held = 1;
    q->deadline = g_get_monotonic_time() + ION_IME_ANSWER_TIMEOUT_MS * 1000;
    q->event = gdk_event_ref(ev);
    ownChar(ev, q->own);
    buildKey(st, ev, kind, 0, q->own, &q->passed);
    awaitEvent(st, ev);
    armAnswerTimer(st);
}

static void onPointer(IonLinuxWindowState *st, GtkEventController *controller, GdkEvent *ev) {
    double px, py;
    switch (gdk_event_get_event_type(ev)) {
        case GDK_BUTTON_PRESS: {
            int b = ionButton(gdk_button_event_get_button(ev));
            if (!b || !clientPoint(st, ev, &px, &py)) return;
            s_buttonsDown |= 1 << b;
            pushPointer(st, ION_INPUT_BUTTON, controller, px, py, b, 1, 0);
            break;
        }
        case GDK_BUTTON_RELEASE: {
            int b = ionButton(gdk_button_event_get_button(ev));
            if (!b || !(s_buttonsDown & (1 << b))) return;
            s_buttonsDown &= ~(1 << b);
            clientPoint(st, ev, &px, &py);
            pushPointer(st, ION_INPUT_BUTTON, controller, px, py, b, 0, 0);
            break;
        }
        case GDK_MOTION_NOTIFY: {
            int inside = clientPoint(st, ev, &px, &py);
            if (!inside && !s_buttonsDown) {
                pushLeave(st, controller);
                return;
            }
            double dx = st->pointerKnown ? px - st->lastX : 0;
            double dy = st->pointerKnown ? py - st->lastY : 0;
            st->pointerKnown = 1;
            st->lastX = px;
            st->lastY = py;
            pushPointer(st, ION_INPUT_MOTION, controller, px, py, dx, dy, 0);
            break;
        }
        case GDK_SCROLL: {
            double dx = 0, dy = 0;
            int unit = ION_WHEEL_LINE;
            switch (gdk_scroll_event_get_direction(ev)) {
                case GDK_SCROLL_UP:     dy = 1; break;
                case GDK_SCROLL_DOWN:   dy = -1; break;
                case GDK_SCROLL_LEFT:   dx = -1; break;
                case GDK_SCROLL_RIGHT:  dx = 1; break;
                case GDK_SCROLL_SMOOTH: {
                    gdk_scroll_event_get_deltas(ev, &dx, &dy);
                    dy = -dy;
                    if (gdk_scroll_event_get_unit(ev) == GDK_SCROLL_UNIT_SURFACE) {
                        double scale = ionLinuxScale(st);
                        dx *= scale;
                        dy *= scale;
                        unit = ION_WHEEL_PIXEL;
                    }
                    break;
                }
                default: return;
            }
            if (!clientPoint(st, ev, &px, &py)) return;
            pushPointer(st, ION_INPUT_WHEEL, controller, px, py, dx, dy, unit);
            break;
        }
        default:
            break;
    }
}

static gboolean onEvent(GtkEventControllerLegacy *controller, GdkEvent *ev, gpointer data) {
    IonLinuxWindowState *st = (IonLinuxWindowState *)data;
    switch (gdk_event_get_event_type(ev)) {
        case GDK_KEY_PRESS:
        case GDK_KEY_RELEASE:
            if (contentHasKeyboard(st)) onKey(st, ev);
            break;
        default:
            onPointer(st, GTK_EVENT_CONTROLLER(controller), ev);
            break;
    }
    return FALSE;
}

static void onLeave(GtkEventControllerMotion *controller, gpointer data) {
    pushLeave((IonLinuxWindowState *)data, GTK_EVENT_CONTROLLER(controller));
}

// Outside filter_keypress a commit answers the oldest held press: exactly that key's own
// character with nothing composed is a pass-through (IBus commits it from gtk_im_context_filter_key).
static void onCommit(GtkIMContext *im, gchar *str, gpointer data) {
    (void)im;
    IonLinuxWindowState *st = (IonLinuxWindowState *)data;
    if (st == s_filterWindow) {
        g_string_append(s_filterCommit, str);
        return;
    }
    IonInputRecord r;
    textRecord(st, str, &r);
    QueuedRecord *q = oldestHeld(st);
    if (!q) {
        emit(st, &r);
    } else if (!st->imComposing && q->own[0] && strcmp(str, q->own) == 0) {
        answer(q, &q->passed);
    } else {
        answer(q, NULL);
        emitAfter(st, q, &r);
    }
    flushKeyQueue(st);
}

// A preedit that shows text answers the oldest held press: the IM composes with it.
static void onPreeditChanged(GtkIMContext *im, gpointer data) {
    IonLinuxWindowState *st = (IonLinuxWindowState *)data;
    gchar *str = NULL;
    gint cursor = 0;
    gtk_im_context_get_preedit_string(im, &str, NULL, &cursor);
    st->imComposing = str && str[0];
    IonInputRecord r;
    memset(&r, 0, sizeof r);
    r.type = ION_INPUT_PREEDIT;
    r.window = st->id;
    r.text = str ? str : "";
    r.p1 = str ? (double)ion_utf16_units(str, cursor) : 0;
    if (st == s_filterWindow) s_filterPreedit = 1;
    QueuedRecord *q = st == s_filterWindow ? s_answering : oldestHeld(st);
    if (q) {
        g_queue_insert_before(&st->keyQueue, q->link, newQueued(&r));
        if (st != s_filterWindow && st->imComposing) answer(q, NULL);
    } else {
        emit(st, &r);
    }
    if (st != s_filterWindow) flushKeyQueue(st);
    g_free(str);
}

// Capture phase: the window's controllers see an event before the webview it targets does.
void ionLinuxAttachInput(IonLinuxWindowState *st) {
    st->im = gtk_im_multicontext_new();
    gtk_im_context_set_client_widget(st->im, st->window);
    g_signal_connect(st->im, "commit", G_CALLBACK(onCommit), st);
    g_signal_connect(st->im, "preedit-changed", G_CALLBACK(onPreeditChanged), st);

    GtkEventController *legacy = gtk_event_controller_legacy_new();
    gtk_event_controller_set_propagation_phase(legacy, GTK_PHASE_CAPTURE);
    g_signal_connect(legacy, "event", G_CALLBACK(onEvent), st);
    gtk_widget_add_controller(st->window, legacy);

    GtkEventController *motion = gtk_event_controller_motion_new();
    gtk_event_controller_set_propagation_phase(motion, GTK_PHASE_CAPTURE);
    g_signal_connect(motion, "leave", G_CALLBACK(onLeave), st);
    gtk_widget_add_controller(st->window, motion);
}

void ionLinuxDetachInput(IonLinuxWindowState *st) {
    gtk_im_context_set_client_widget(st->im, NULL);
    g_signal_handlers_disconnect_by_data(st->im, st);
    g_object_unref(st->im);
    st->im = NULL;
    if (st->keyQueueTimer) g_source_remove(st->keyQueueTimer);
    st->keyQueueTimer = 0;
    g_queue_clear_full(&st->keyQueue, (GDestroyNotify)freeQueued);
    for (size_t i = 0; i < G_N_ELEMENTS(st->imAwaited); i++)
        if (st->imAwaited[i]) gdk_event_unref(st->imAwaited[i]);
}

void ionWindowSetOptionAsAlt(IonWindowId id, int sides) {
    (void)id; (void)sides;
}

void ionWindowSetImeRect(IonWindowId id, int x, int y, int w, int h) {
    IonLinuxWindowState *st = ionLinuxWindowState(id);
    if (!st) return;
    double scale = ionLinuxScale(st);
    graphene_point_t in = GRAPHENE_POINT_INIT((float)(x / scale), (float)(y / scale)), out;
    if (!gtk_widget_compute_point(st->root, st->window, &in, &out)) return;
    GdkRectangle r = { (int)out.x, (int)out.y, (int)(w / scale), (int)(h / scale) };
    gtk_im_context_set_cursor_location(st->im, &r);
}
