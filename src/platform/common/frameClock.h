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
// The window whose display should pace the frame tick: the one that requested a frame last
// while it is still due, else the first due window, else -1.
int  ion_frame_pacing_window(void);

#ifdef __cplusplus
}
#endif

#endif
