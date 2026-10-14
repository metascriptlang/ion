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

static GMutex   s_wakeLock;
static GCond    s_wakeCond;
static gboolean s_wakePending;

void ionWakeLoop(void) {
    g_mutex_lock(&s_wakeLock);
    s_wakePending = TRUE;
    g_cond_signal(&s_wakeCond);
    g_mutex_unlock(&s_wakeLock);
}

static int drain(void) {
    if (ion_wevt_pop(&s_lastWevtId, &s_lastWevtType)) return 3;
    if (ion_queue_pop()) return 2;
    if (ion_input_next()) return 4;
    return 0;
}

int ionPollEvent(void) {
    int got = drain();
    if (got) return got;

    while (gtk_events_pending()) {
        gtk_main_iteration_do(FALSE);
    }

    if (s_quitRequested) return 1;
    got = drain();
    if (got) return got;

    // 16ms — match macOS SDL_WaitEventTimeout(16) cadence; ionWakeLoop ends it early
    g_mutex_lock(&s_wakeLock);
    if (!s_wakePending) g_cond_wait_until(&s_wakeCond, &s_wakeLock, g_get_monotonic_time() + 16000);
    gboolean woken = s_wakePending;
    s_wakePending = FALSE;
    g_mutex_unlock(&s_wakeLock);
    if (woken) return 6;
    if (ion_frame_emit((double)g_get_monotonic_time() / 1000.0) > 0 && ion_input_next()) return 4;
    return 0;
}

msString    ionMessageName(void)     { return cStringToMs(ion_queue_last_name()); }
msString    ionMessagePayload(void)  { return cStringToMs(ion_queue_last_payload()); }
IonWindowId ionWindowEventId(void)   { return s_lastWevtId; }
int         ionWindowEventType(void) { return s_lastWevtType; }

void ionLoopArm(void) {}
