// The msc runtime (and, with ION_PROBE_VOID, Void) symbols the linked C references; contentXid.c reaches none of them.
#include <stdio.h>
#include <stdlib.h>

static void unreached(const char *name) {
    fprintf(stderr, "contentXid: %s reached, the probe has no msc runtime\n", name);
    abort();
}

void msStringFromCStr(void) { unreached("msStringFromCStr"); }
void msNextTimerDelayMs(void) { unreached("msNextTimerDelayMs"); }
void msGetDispatcher(void) { unreached("msGetDispatcher"); }
void msAdjustTimeout(void) { unreached("msAdjustTimeout"); }

#ifdef ION_PROBE_VOID
// Void's frame timing is implemented in MetaScript; only voidLinuxRun reaches it.
void voidFrameTimingReset(void) { unreached("voidFrameTimingReset"); }
void voidFrameTimingStep(void) { unreached("voidFrameTimingStep"); }
#endif
