#ifndef ION_TEST_WINDOW_FRAME_HELPER_H
#define ION_TEST_WINDOW_FRAME_HELPER_H

void wfSizing(int x, int y, int w, int h, int edges, int decoW, int decoH, int cellW, int cellH, int baseW, int baseH);
void wfAreasClear(void);
void wfAreaAdd(int x, int y, int w, int h);
void wfFit(int x, int y, int w, int h);

#endif
