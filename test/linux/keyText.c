// A plain key's text reaches the app once, on its key record; a dead-key composition still ends
// in one text record. Driven through XTest under Xvfb with GTK's simple IM (keyText.sh).
#include "platform/bridge.h"
#include "platform/common/inputEvents.h"

#include <gtk/gtk.h>
#include <gdk/x11/gdkx.h>
#include <X11/Xlib.h>
#include <X11/keysym.h>
#include <X11/extensions/XTest.h>
#include <stdio.h>
#include <string.h>

GtkWidget *ionGetMainWindow(void);

static int s_failures, s_keyText, s_textRecords, s_preedits, s_imeKeys;
static char s_keyTexts[64], s_texts[64];

int __real_ion_input_push_record(const IonInputRecord *r);
int __wrap_ion_input_push_record(const IonInputRecord *r) {
    if (r->type == ION_INPUT_KEY && r->p1 == 1 && r->imeHandled) s_imeKeys++;
    if (r->type == ION_INPUT_KEY && r->p1 != 2 && !r->imeHandled && r->text && r->text[0]) { s_keyText++; strncat(s_keyTexts, r->text, 20); }
    if (r->type == ION_INPUT_TEXT) { s_textRecords++; strncat(s_texts, r->text, 20); }
    if (r->type == ION_INPUT_PREEDIT && r->text && r->text[0]) s_preedits++;
    return __real_ion_input_push_record(r);
}

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

static void reset(void) { s_keyText = s_textRecords = s_preedits = s_imeKeys = 0; s_keyTexts[0] = s_texts[0] = 0; }

static void tap(Display *dpy, KeyCode code) {
    XTestFakeKeyEvent(dpy, code, True, 0);
    XTestFakeKeyEvent(dpy, code, False, 0);
    XFlush(dpy);
    pump(150);
}

int main(void) {
    if (!ionRequestX11()) { printf("FAIL no X server\n"); return 1; }
    IonWindowId id = ionCreateWindow("main", "keyText", 400, 300, ION_WIN_DEFAULT);
    pump(800);
    Display *dpy = XOpenDisplay(NULL);
    Window top = gdk_x11_surface_get_xid(gtk_native_get_surface(GTK_NATIVE(ionGetMainWindow())));
    XSetInputFocus(dpy, top, RevertToParent, CurrentTime);
    XFlush(dpy);
    pump(300);
    (void)id;

    const char *im = getenv("GTK_IM_MODULE") ? getenv("GTK_IM_MODULE") : "";
    int simple = strcmp(im, "gtk-im-context-simple") == 0;
    reset();
    tap(dpy, XKeysymToKeycode(dpy, XK_a));
    tap(dpy, XKeysymToKeycode(dpy, XK_b));
    pump(300);
    char seen[64];
    snprintf(seen, sizeof seen, "%s%s", s_keyTexts, s_texts);
    printf("plain (%s): key records with text %d \"%s\", imeHandled presses %d, text records %d \"%s\"\n",
           im, s_keyText, s_keyTexts, s_imeKeys, s_textRecords, s_texts);
    check(strcmp(seen, "ab") == 0, "ab reaches the app once: on key records not marked imeHandled, or as text records");
    check(s_textRecords == 0 || s_imeKeys == 2, "a key whose text comes as a text record is marked imeHandled");
    if (simple) check(s_keyText == 2 && s_textRecords == 0, "the simple IM's synchronous commit rides the key record");
    if (!simple) check(s_imeKeys == 2 && s_textRecords == 2, "the input method took both presses and committed after filter_keypress");
    if (!simple) { printf("%s, %d failure(s)\n", s_failures ? "RED" : "GREEN", s_failures); return s_failures ? 1 : 0; }

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
    printf("dead key: preedits %d, key records with text %d \"%s\", text records %d \"%s\"\n", s_preedits, s_keyText, s_keyTexts, s_textRecords, s_texts);
    check(s_textRecords == 1 && strcmp(s_texts, "\xc3\xa9") == 0, "dead acute then e ends in one text record \"\xc3\xa9\"");
    check(s_keyText == 0, "the composing keys carry no text of their own");

    printf("%s, %d failure(s)\n", s_failures ? "RED" : "GREEN", s_failures);
    return s_failures ? 1 : 0;
}
