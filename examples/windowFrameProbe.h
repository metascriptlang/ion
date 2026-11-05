#ifndef ION_EXAMPLE_WINDOW_FRAME_PROBE_H
#define ION_EXAMPLE_WINDOW_FRAME_PROBE_H

// Native readbacks for examples/windowFrame.ms: windowFrameProbe.c on Windows, .m on macOS.
int wpPixel(int window, int x, int y);
int wpZoomed(int window);
int wpVisible(int window);
int wpSteps(int window, int cellW, int cellH, int baseW, int baseH);
int wpOnScreen(int x, int y);

#endif
