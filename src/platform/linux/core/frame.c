#include "../internal.h"
#include "../../common/frameClock.h"
#include "../../common/windowRegistry.h"

static IonLinuxWindowState *s_driver;
static guint s_tickId;

static gboolean onTick(GtkWidget *widget, GdkFrameClock *clock, gpointer data) {
    (void)widget; (void)data;
    ion_frame_emit((double)gdk_frame_clock_get_frame_time(clock) / 1000.0);
    return G_SOURCE_CONTINUE;
}

static IonLinuxWindowState *firstVisible(void) {
    for (IonWindowId i = ion_registry_next(ION_WINDOW_INVALID);
         i != ION_WINDOW_INVALID;
         i = ion_registry_next(i)) {
        IonLinuxWindowState *st = ionLinuxWindowState(i);
        if (st && gtk_widget_get_visible(st->window) && !st->iconified) return st;
    }
    return NULL;
}

static void stopTick(void) {
    if (s_driver && s_tickId) gtk_widget_remove_tick_callback(s_driver->window, s_tickId);
    s_driver = NULL;
    s_tickId = 0;
}

void ionLinuxFrameSync(void) {
    IonLinuxWindowState *want = ion_frame_wanted() ? firstVisible() : NULL;
    if (want == s_driver) return;
    stopTick();
    if (!want) return;
    s_driver = want;
    s_tickId = gtk_widget_add_tick_callback(want->window, onTick, NULL, NULL);
}

void ionLinuxFrameDetach(IonLinuxWindowState *st) {
    if (st == s_driver) stopTick();
}
