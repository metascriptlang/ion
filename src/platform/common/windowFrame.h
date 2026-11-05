// Window geometry shared by every platform: cell-step resize snapping, fitting a saved frame onto
// the monitors that exist now, and the frame record ionWindowFrameRead fills.

#ifndef ION_WINDOW_FRAME_H
#define ION_WINDOW_FRAME_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    int x, y, width, height;
} IonBox;

// Edges a live resize moves; Windows maps its WMSZ_* side onto these.
#define ION_EDGE_LEFT   1
#define ION_EDGE_RIGHT  2
#define ION_EDGE_TOP    4
#define ION_EDGE_BOTTOM 8

// The size nearest to `size` of the form base + n * cell with n >= 1; `size` when cell <= 0.
int ion_resize_snap(int size, int cell, int base);

// Snaps a window's outer box during a live resize so its client area (outer minus decoW x decoH)
// is base + n * cell on each axis, moving only the dragged edges (winit event_loop.rs WM_SIZING).
void ion_sizing_snap(IonBox *outer, int edges, int decoW, int decoH,
                     int cellW, int cellH, int baseW, int baseH);

// A saved outer box placed onto the work areas that exist now (areas[0] is the primary). The box
// keeps its place while its top edge and ION_FIT_GRIP pixels of its width lie on the work area it
// overlaps most; otherwise it moves inside that area, or the primary when it overlaps none. Its
// size never exceeds that area.
#define ION_FIT_GRIP 48
IonBox ion_box_fit(IonBox box, const IonBox *areas, int count);

// The record ionWindowFrameRead fills and ionWindowFrameX..Maximized (bridge.h) read.
void ion_window_frame_store(int x, int y, int width, int height, int maximized);

#ifdef __cplusplus
}
#endif

#endif
