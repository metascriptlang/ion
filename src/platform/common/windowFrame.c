#include "windowFrame.h"

static IonBox s_frame;
static int s_maximized;

int ion_resize_snap(int size, int cell, int base) {
    if (cell <= 0) return size;
    int n = (size - base + cell / 2) / cell;
    if (size - base + cell / 2 < 0 || n < 1) n = 1;
    return base + n * cell;
}

void ion_sizing_snap(IonBox *outer, int edges, int decoW, int decoH,
                     int cellW, int cellH, int baseW, int baseH) {
    if (cellW > 0 && (edges & (ION_EDGE_LEFT | ION_EDGE_RIGHT))) {
        int width = ion_resize_snap(outer->width - decoW, cellW, baseW) + decoW;
        if (edges & ION_EDGE_LEFT) outer->x += outer->width - width;
        outer->width = width;
    }
    if (cellH > 0 && (edges & (ION_EDGE_TOP | ION_EDGE_BOTTOM))) {
        int height = ion_resize_snap(outer->height - decoH, cellH, baseH) + decoH;
        if (edges & ION_EDGE_TOP) outer->y += outer->height - height;
        outer->height = height;
    }
}

static int overlap(int a, int aLen, int b, int bLen) {
    int lo = a > b ? a : b;
    int hi = a + aLen < b + bLen ? a + aLen : b + bLen;
    return hi > lo ? hi - lo : 0;
}

static int clampInt(int v, int lo, int hi) {
    return v < lo ? lo : v > hi ? hi : v;
}

IonBox ion_box_fit(IonBox box, const IonBox *areas, int count) {
    if (count <= 0) return box;
    int best = 0;
    long long bestArea = 0;
    for (int i = 0; i < count; i++) {
        long long area = (long long)overlap(box.x, box.width, areas[i].x, areas[i].width)
                       * overlap(box.y, box.height, areas[i].y, areas[i].height);
        if (area > bestArea) { best = i; bestArea = area; }
    }
    IonBox a = areas[best];
    if (box.width > a.width) box.width = a.width;
    if (box.height > a.height) box.height = a.height;
    int grip = box.width < ION_FIT_GRIP ? box.width : ION_FIT_GRIP;
    int topOnArea = box.y >= a.y && box.y < a.y + a.height;
    if (topOnArea && overlap(box.x, box.width, a.x, a.width) >= grip) return box;
    box.x = clampInt(box.x, a.x, a.x + a.width - box.width);
    box.y = clampInt(box.y, a.y, a.y + a.height - box.height);
    return box;
}

void ion_window_frame_store(int x, int y, int width, int height, int maximized) {
    s_frame = (IonBox){x, y, width, height};
    s_maximized = maximized != 0;
}

int ionWindowFrameX(void) { return s_frame.x; }
int ionWindowFrameY(void) { return s_frame.y; }
int ionWindowFrameWidth(void) { return s_frame.width; }
int ionWindowFrameHeight(void) { return s_frame.height; }
int ionWindowFrameMaximized(void) { return s_maximized; }
