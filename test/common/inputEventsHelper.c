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

// A wheel record with its unit (ION_WHEEL_PIXEL or ION_WHEEL_LINE) in `key`.
int ionTestPushWheel(int window, double dx, double dy, int unit) {
    IonInputRecord r;
    memset(&r, 0, sizeof r);
    r.type = ION_INPUT_WHEEL;
    r.window = window;
    r.p1 = dx;
    r.p2 = dy;
    r.key = unit;
    return ion_input_push_record(&r);
}
