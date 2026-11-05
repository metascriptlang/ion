#include "windowFrameHelper.h"
#include "../../src/platform/common/windowFrame.h"

static IonBox s_areas[8];
static int s_count;

static void store(IonBox b) {
    ion_window_frame_store(b.x, b.y, b.width, b.height, 0);
}

void wfSizing(int x, int y, int w, int h, int edges, int decoW, int decoH, int cellW, int cellH, int baseW, int baseH) {
    IonBox b = {x, y, w, h};
    ion_sizing_snap(&b, edges, decoW, decoH, cellW, cellH, baseW, baseH);
    store(b);
}

void wfAreasClear(void) { s_count = 0; }

void wfAreaAdd(int x, int y, int w, int h) {
    if (s_count < 8) s_areas[s_count++] = (IonBox){x, y, w, h};
}

void wfFit(int x, int y, int w, int h) {
    store(ion_box_fit((IonBox){x, y, w, h}, s_areas, s_count));
}
