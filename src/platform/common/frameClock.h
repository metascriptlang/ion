#ifndef ION_FRAME_CLOCK_H
#define ION_FRAME_CLOCK_H

#ifdef __cplusplus
extern "C" {
#endif

void ion_frame_surface_open(int surf, int win);
void ion_frame_surface_close(int surf);
void ion_frame_window_state(int win, int active, int visible);

int ion_frame_wanted(void);
int ion_frame_emit(double timeMs);

#ifdef __cplusplus
}
#endif

#endif
