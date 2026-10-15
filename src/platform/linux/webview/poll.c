#include "../state.h"
#include "../internal.h"
#include "../../bridge.h"
#include "../../common/queue.h"
#include "../../common/inputEvents.h"
#include "../../common/frameClock.h"
#include "../../common/windowEvents.h"

#include <gtk/gtk.h>

static IonWindowId s_lastWevtId   = ION_WINDOW_INVALID;
static int         s_lastWevtType = 0;
static gint        s_wakePending;

void ionWakeLoop(void) {
    g_atomic_int_set(&s_wakePending, 1);
    g_main_context_wakeup(NULL);
}

static int drain(void) {
    if (ion_wevt_pop(&s_lastWevtId, &s_lastWevtType)) return 3;
    if (ion_queue_pop()) return 2;
    if (ion_input_next()) return 4;
    return 0;
}

static gboolean keepWaking(gpointer data) {
    (void)data;
    return G_SOURCE_CONTINUE;
}

// A 16 ms timer bounds each blocking iteration so msc's loop runs at the macOS cadence;
// ionWakeLoop ends the wait early.
int ionPollEvent(void) {
    static int timerInstalled;
    if (!timerInstalled) {
        timerInstalled = 1;
        g_timeout_add(16, keepWaking, NULL);
    }

    int got = drain();
    if (got) return got;

    ionLinuxFrameSync();
    while (g_main_context_iteration(NULL, FALSE)) {}

    if (s_quitRequested) return 1;
    got = drain();
    if (got) return got;

    if (!g_atomic_int_get(&s_wakePending)) g_main_context_iteration(NULL, TRUE);
    got = drain();
    if (got) return got;
    if (g_atomic_int_compare_and_exchange(&s_wakePending, 1, 0)) return 6;
    return 0;
}

msString    ionMessageName(void)     { return cStringToMs(ion_queue_last_name()); }
msString    ionMessagePayload(void)  { return cStringToMs(ion_queue_last_payload()); }
IonWindowId ionWindowEventId(void)   { return s_lastWevtId; }
int         ionWindowEventType(void) { return s_lastWevtType; }

void ionLoopArm(void) {}
