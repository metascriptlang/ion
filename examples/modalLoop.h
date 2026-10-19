#ifndef ION_EXAMPLE_MODAL_LOOP_H
#define ION_EXAMPLE_MODAL_LOOP_H

#ifdef __cplusplus
extern "C" {
#endif

// Finds the probe's own window by title, subclasses it to timestamp WM_ENTERSIZEMOVE and
// WM_EXITSIZEMOVE, and starts a thread that calls ionWakeLoop every 5 ms. 0 when no window.
int  modalInit(void);
// Counts one event of a kind: 0 frame, 1 interval run, 2 wake handler run.
void modalCount(int kind);
// Starts one 2 s scenario on a helper thread: 0 control, 1 keyboard move (SC_MOVE), 2 keyboard size (SC_SIZE).
void modalRun(int scenario);
// Nonzero once the last started scenario has printed its line.
int  modalDone(void);

#ifdef __cplusplus
}
#endif

#endif
