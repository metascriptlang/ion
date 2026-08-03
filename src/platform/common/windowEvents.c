#include "windowEvents.h"

#include <stdio.h>

#define ION_WEVT_CAP 64

typedef struct {
    IonWindowId windowId;
    int         eventType;
} ion_wevt_entry_t;

static ion_wevt_entry_t s_ring[ION_WEVT_CAP];
static int s_head = 0;   // next pop index
static int s_tail = 0;   // next push index
static int s_count = 0;

int ion_wevt_push(IonWindowId windowId, int eventType) {
    if (s_count >= ION_WEVT_CAP) {
        fprintf(stderr, "[ion] wevt_push: ring full; event dropped "
                        "(windowId=%d type=%d)\n", (int)windowId, eventType);
        return -1;
    }
    s_ring[s_tail].windowId  = windowId;
    s_ring[s_tail].eventType = eventType;
    s_tail = (s_tail + 1) % ION_WEVT_CAP;
    s_count = s_count + 1;
    return 0;
}

int ion_wevt_pop(IonWindowId *outId, int *outType) {
    if (s_count == 0) return 0;
    if (outId)   *outId   = s_ring[s_head].windowId;
    if (outType) *outType = s_ring[s_head].eventType;
    s_head = (s_head + 1) % ION_WEVT_CAP;
    s_count = s_count - 1;
    return 1;
}
