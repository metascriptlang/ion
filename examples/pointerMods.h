#ifndef ION_EXAMPLE_POINTER_MODS_H
#define ION_EXAMPLE_POINTER_MODS_H

#ifdef __cplusplus
extern "C" {
#endif

// Sends WM_MOUSEMOVE, WM_LBUTTONDOWN and WM_LBUTTONUP at client (x, y) straight to ion's main
// window procedure, for examples/pointerMods.ms. shift: 1 holds Shift through the thread
// keyboard state for the call, 0 releases it; the previous state is restored afterwards.
void pmClick(int shift, int x, int y);
void pmClose(void);

#ifdef __cplusplus
}
#endif

#endif
