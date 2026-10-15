#ifndef ION_EXAMPLE_MULTI_WINDOW_H
#define ION_EXAMPLE_MULTI_WINDOW_H

#ifdef __cplusplus
extern "C" {
#endif

void mwClick(int window, int x, int y);
void mwKey(int window, int vk, int scancode);
void mwClose(int window);
int  mwPixel(int window, int x, int y);

#ifdef __cplusplus
}
#endif

#endif
