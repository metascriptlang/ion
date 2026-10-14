#include "mscLoop.h"
#include "runtime/promise/dispatch.h"

int ion_msc_next_delay_ms(void) {
    msDispatcher *d = msGetDispatcher();
    bool didWork = false;
    int nextTimer = msProcessTimers(d, &didWork);
    return msAdjustTimeout(d, -1, nextTimer);
}
