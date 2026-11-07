// A plain key's text reaches the app once, on its key record; a dead-key composition still ends
// in one text record. Driven through XTest under Xvfb (keyText.sh) with GTK's simple IM, with
// IBus outside its sync mode, and with ion-probe-async, which answers as fcitx5-gtk does.
#include "platform/bridge.h"
#include "platform/common/inputEvents.h"

#include <gtk/gtk.h>
#include <gdk/x11/gdkx.h>
#include <X11/Xlib.h>
#include <X11/keysym.h>
#include <X11/extensions/XTest.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

GtkWidget *ionGetMainWindow(void);

static int s_failures, s_keyText, s_textRecords, s_preedits, s_imeKeys, s_imeReleases, s_lastPressIme;
static char s_keyTexts[64], s_texts[64], s_seq[256], s_lastAllMods[8];
static gint64 s_lastPressAt;

// The key records in order: +a press not imeHandled, *a press imeHandled, -a release,
// ~a release imeHandled, [x] a text record x.
static void seq(char mark, unsigned ch) {
    size_t n = strlen(s_seq);
    if (n + 2 < sizeof s_seq) { s_seq[n] = mark; s_seq[n + 1] = ch >= 0x20 && ch < 0x7f ? (char)ch : '?'; s_seq[n + 2] = 0; }
}

static void seqText(const char *s) {
    strncat(s_seq, "[", sizeof s_seq - strlen(s_seq) - 1);
    strncat(s_seq, s, sizeof s_seq - strlen(s_seq) - 1);
    strncat(s_seq, "]", sizeof s_seq - strlen(s_seq) - 1);
}

int __real_ion_input_push_record(const IonInputRecord *r);
int __wrap_ion_input_push_record(const IonInputRecord *r) {
    if (r->type == ION_INPUT_KEY && r->p1 != 0) {
        s_lastPressAt = g_get_monotonic_time();
        s_lastPressIme = r->imeHandled;
        g_strlcpy(s_lastAllMods, r->allModsText ? r->allModsText : "", sizeof s_lastAllMods);
    }
    if (r->type == ION_INPUT_KEY && r->p1 == 1 && r->imeHandled) s_imeKeys++;
    if (r->type == ION_INPUT_KEY && r->p1 == 0 && r->imeHandled) s_imeReleases++;
    if (r->type == ION_INPUT_KEY && r->p1 != 2 && !r->imeHandled && r->text && r->text[0]) { s_keyText++; strncat(s_keyTexts, r->text, 20); }
    if (r->type == ION_INPUT_KEY) seq(r->p1 == 0 ? (r->imeHandled ? '~' : '-') : (r->imeHandled ? '*' : '+'), r->unshifted);
    if (r->type == ION_INPUT_TEXT) { s_textRecords++; strncat(s_texts, r->text, 20); seqText(r->text); }
    if (r->type == ION_INPUT_PREEDIT && r->text && r->text[0]) s_preedits++;
    return __real_ion_input_push_record(r);
}

// fcitx5-gtk's asynchronous mode (gtk4/fcitximcontext.cpp, fcitx_im_context_filter_keypress
// and _fcitx_im_context_process_key_cb): filter_keypress keeps the event as pending and returns
// TRUE; when the daemon replies "not handled" the event goes back on the display with
// gdk_display_put_event, and its second pass through filter_keypress reaches the simple IM.
#define IM_EXTENSION_POINT "gtk-im-module"   // GTK_IM_MODULE_EXTENSION_POINT_NAME, gtk/gtkimmoduleprivate.h
typedef struct { GtkIMContextSimple parent; GHashTable *pending; } ProbeAsyncIM;
typedef struct { GtkIMContextSimpleClass parent_class; } ProbeAsyncIMClass;
G_DEFINE_TYPE(ProbeAsyncIM, probe_async_im, GTK_TYPE_IM_CONTEXT_SIMPLE)

static gboolean putBack(gpointer data) {
    GdkEvent *ev = data;
    gdk_display_put_event(gdk_event_get_display(ev), ev);
    gdk_event_unref(ev);
    return G_SOURCE_REMOVE;
}

static gboolean probeFilter(GtkIMContext *c, GdkEvent *ev) {
    ProbeAsyncIM *p = (ProbeAsyncIM *)c;
    if (g_hash_table_remove(p->pending, ev))
        return GTK_IM_CONTEXT_CLASS(probe_async_im_parent_class)->filter_keypress(c, ev);
    g_hash_table_add(p->pending, ev);
    g_timeout_add(2, putBack, gdk_event_ref(ev));
    return TRUE;
}

static void probe_async_im_init(ProbeAsyncIM *p) { p->pending = g_hash_table_new(NULL, NULL); }
static void probe_async_im_class_init(ProbeAsyncIMClass *k) { GTK_IM_CONTEXT_CLASS(k)->filter_keypress = probeFilter; }

static void check(int ok, const char *what) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok) s_failures++;
}

static gboolean pumpDone(gpointer p) { *(int *)p = 1; return G_SOURCE_REMOVE; }

static void pump(int ms) {
    int done = 0;
    g_timeout_add(ms, pumpDone, &done);
    while (!done) g_main_context_iteration(NULL, TRUE);
}

static void reset(void) {
    s_keyText = s_textRecords = s_preedits = s_imeKeys = s_imeReleases = 0;
    s_keyTexts[0] = s_texts[0] = s_seq[0] = 0;
}

static void key(Display *dpy, KeyCode code, Bool down) { XTestFakeKeyEvent(dpy, code, down, 0); }

static void tap(Display *dpy, KeyCode code) {
    key(dpy, code, True);
    key(dpy, code, False);
    XFlush(dpy);
    pump(150);
}

static int cmpLong(const void *a, const void *b) { return *(const long *)a < *(const long *)b ? -1 : *(const long *)a > *(const long *)b; }

// Time from the XTest press to its key record over n letter presses.
static void latency(Display *dpy, int n, const char *im) {
    long us[64];
    int got = 0;
    for (int i = 0; i < n && i < 64; i++) {
        KeyCode code = XKeysymToKeycode(dpy, XK_a + i % 26);
        s_lastPressAt = 0;
        gint64 sent = g_get_monotonic_time();
        key(dpy, code, True);
        XFlush(dpy);
        pump(60);
        if (s_lastPressAt) us[got++] = (long)(s_lastPressAt - sent);
        key(dpy, code, False);
        XFlush(dpy);
        pump(60);
    }
    qsort(us, got, sizeof us[0], cmpLong);
    printf("latency (%s): %d of %d presses, XTest press to key record p50 %.2f ms max %.2f ms\n",
           im, got, n, got ? us[got / 2] / 1000.0 : -1, got ? us[got - 1] / 1000.0 : -1);
    check(got == n, "every press reached a key record");
}

int main(void) {
    const char *im = getenv("GTK_IM_MODULE") ? getenv("GTK_IM_MODULE") : "";
    int ibus = strcmp(im, "ibus") == 0;
    int ibusAsync = ibus && g_strcmp0(getenv("IBUS_ENABLE_SYNC_MODE"), "0") == 0;
    g_io_extension_point_register(IM_EXTENSION_POINT);
    g_io_extension_point_implement(IM_EXTENSION_POINT, probe_async_im_get_type(), "ion-probe-async", 0);
    if (!ionRequestX11()) { printf("FAIL no X server\n"); return 1; }
    IonWindowId id = ionCreateWindow("main", "keyText", 400, 300, ION_WIN_DEFAULT);
    pump(800);
    Display *dpy = XOpenDisplay(NULL);
    Window top = gdk_x11_surface_get_xid(gtk_native_get_surface(GTK_NATIVE(ionGetMainWindow())));
    XSetInputFocus(dpy, top, RevertToParent, CurrentTime);
    XFlush(dpy);
    pump(300);
    (void)id;

    KeyCode a = XKeysymToKeycode(dpy, XK_a), b = XKeysymToKeycode(dpy, XK_b);
    reset();
    tap(dpy, a);
    tap(dpy, b);
    pump(300);
    printf("plain (%s): %s; key records with text %d \"%s\", imeHandled presses %d releases %d, text records %d \"%s\"\n",
           im, s_seq, s_keyText, s_keyTexts, s_imeKeys, s_imeReleases, s_textRecords, s_texts);
    check(strcmp(s_seq, "+a-a+b-b") == 0, "ab: press a with text a, its release, press b with text b, its release");
    check(s_keyText == 2 && strcmp(s_keyTexts, "ab") == 0, "the presses carry their text a and b");
    check(s_imeKeys == 0 && s_imeReleases == 0 && s_textRecords == 0, "no key marked imeHandled and no text record");

    // Both presses before either release: the second press and the releases wait behind the first.
    reset();
    key(dpy, a, True);
    key(dpy, b, True);
    key(dpy, a, False);
    key(dpy, b, False);
    XFlush(dpy);
    pump(400);
    printf("overlapped (%s): %s\n", im, s_seq);
    check(strcmp(s_seq, "+a+b-a-b") == 0, "overlapped presses and releases keep their order and text");

    // Ctrl+C has no text: IBus passing it through gives no answer GTK shows; ion-probe-async re-delivers it.
    KeyCode ctrl = XKeysymToKeycode(dpy, XK_Control_L), c = XKeysymToKeycode(dpy, XK_c);
    key(dpy, ctrl, True);
    XFlush(dpy);
    pump(150);
    s_lastPressAt = 0;
    gint64 sent = g_get_monotonic_time();
    key(dpy, c, True);
    XFlush(dpy);
    pump(300);
    printf("ctrl+c (%s): imeHandled %d allModsText 0x%02x after %.2f ms\n", im, s_lastPressIme,
           (unsigned char)s_lastAllMods[0], s_lastPressAt ? (s_lastPressAt - sent) / 1000.0 : -1);
    if (ibusAsync) check(s_lastPressIme == 1, "asynchronous IBus: Ctrl+C has no observable answer and is pushed imeHandled at the timeout");
    else check(s_lastPressIme == 0 && s_lastAllMods[0] == 3, "Ctrl+C is a key record with allModsText \\x03, not imeHandled");
    key(dpy, c, False);
    key(dpy, ctrl, False);
    XFlush(dpy);
    pump(150);

    latency(dpy, 50, im);

    // Put dead_acute on a spare keycode, as a layout with dead keys has it.
    int lo, hi;
    XDisplayKeycodes(dpy, &lo, &hi);
    KeyCode dead = (KeyCode)hi;
    KeySym sym = XK_dead_acute;
    XChangeKeyboardMapping(dpy, dead, 1, &sym, 1);
    XSync(dpy, False);
    pump(300);
    reset();
    tap(dpy, dead);
    tap(dpy, XKeysymToKeycode(dpy, XK_e));
    pump(300);
    printf("dead key (%s): %s; preedits %d, key records with text %d \"%s\", text records %d \"%s\"\n",
           im, s_seq, s_preedits, s_keyText, s_keyTexts, s_textRecords, s_texts);
    if (!ibusAsync) {
        check(strcmp(s_seq, "*?~?*e[\xc3\xa9]~e") == 0, "dead acute and e are imeHandled, press and release, and \xc3\xa9 follows e's press as one text record");
        if (!ibus) check(s_preedits >= 1, "dead acute shows a preedit");
    }
    printf("%s, %d failure(s)\n", s_failures ? "RED" : "GREEN", s_failures);
    return s_failures ? 1 : 0;
}
