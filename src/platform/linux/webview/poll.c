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

    g_usleep(16000);  // 16ms — match macOS SDL_WaitEventTimeout(16) cadence
    if (ion_frame_emit((double)g_get_monotonic_time() / 1000.0) > 0 && ion_input_next()) return 4;
    return 0;
}

msString    ionMessageName(void)     { return cStringToMs(ion_queue_last_name()); }
msString    ionMessagePayload(void)  { return cStringToMs(ion_queue_last_payload()); }
IonWindowId ionWindowEventId(void)   { return s_lastWevtId; }
int         ionWindowEventType(void) { return s_lastWevtType; }
