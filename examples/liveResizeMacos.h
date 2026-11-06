#ifndef ION_EXAMPLE_LIVE_RESIZE_MACOS_H
#define ION_EXAMPLE_LIVE_RESIZE_MACOS_H

// Drives a live resize of an ion window from inside the app, for examples/liveResizeMacos.ms.
// lrBind takes the window's compositor root and timestamps AppKit's live-resize start and end.
void lrBind(void *root);
// Counts one event of a kind: 0 frame, 1 interval run, 2 resized window event.
void lrCount(int kind);
// Starts one 2 s scenario: 0 control (no drag), 1 a corner drag posted as NSEvents to the
// app's own queue, so no Accessibility permission is needed.
void lrRun(int scenario);
// Nonzero once the last started scenario has printed its line.
int  lrDone(void);
// 0 when every scenario passed.
int  lrFailures(void);

#endif
