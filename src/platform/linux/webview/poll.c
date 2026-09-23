// Ion Linux — event pump + IPC message accessor.
//
// Each ionPollEvent tick:
//   1. drain one queued IPC msg → return 2
//   2. pump pending GTK events (non-blocking) — drives signal callbacks
//   3. if window destroyed → return 1
//   4. drain queue again → return 2
//   5. else sleep 16ms (60Hz idle pace) → return 0
//
// Phase 1: WebKitGTK not yet wired, so IPC queue only fills from chrome
// callbacks (tray/notify) which are also stubbed. Loop just keeps the
// window responsive.

#include "../state.h"
#include "../internal.h"
#include "../../bridge.h"
#include "../../common/queue.h"
#include "../../common/inputEvents.h"

#include <gtk/gtk.h>

int ionPollEvent(void) {
    if (ion_queue_pop()) return 2;
    if (ion_input_next()) return 4;

    while (gtk_events_pending()) {
        gtk_main_iteration_do(FALSE);
    }

    if (ion_queue_pop()) return 2;
    if (s_mainWindow == NULL) return 1;

    g_usleep(16000);  // 16ms — match macOS SDL_WaitEventTimeout(16) cadence
    return 0;
}

msString ionMessageName(void)    { return cStringToMs(ion_queue_last_name()); }
msString ionMessagePayload(void) { return cStringToMs(ion_queue_last_payload()); }

// ionEvalJS now lives in webview/eval.c.
