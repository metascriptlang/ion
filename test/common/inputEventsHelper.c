#include "../../src/platform/common/inputEvents.h"

#include <string.h>

// A pointer record as a platform producer pushes it: a window, a position and modifier bits.
int ionTestPushPointer(int type, int window, double x, double y, double p1, double p2, int mods) {
    IonInputRecord r;
    memset(&r, 0, sizeof r);
    r.type = type;
    r.window = window;
    r.x = x;
    r.y = y;
    r.p1 = p1;
    r.p2 = p2;
    r.mods = mods;
    return ion_input_push_record(&r);
}
