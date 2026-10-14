#ifndef ION_FRAME_CLOCK_H
#define ION_FRAME_CLOCK_H

#ifdef __cplusplus
extern "C" {
#endif

void ion_frame_window_open(int win);
void ion_frame_window_close(int win);
void ion_frame_window_state(int win, int active, int visible);
int  ion_frame_wanted(void);
int  ion_frame_emit(double timeMs);

#ifdef __cplusplus
}
#endif

#endif
