#include "mscLoop.h"
#include "runtime/promise/dispatch.h"

int ion_msc_next_delay_ms(void) {
    return msAdjustTimeout(msGetDispatcher(), -1, msNextTimerDelayMs());
}
