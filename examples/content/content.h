#ifndef ION_EXAMPLE_CONTENT_H
#define ION_EXAMPLE_CONTENT_H

#ifdef __cplusplus
extern "C" {
#endif

int   contentAttach(void *parent, void *child, int above);
void  contentDetach(void *parent, void *child);
void  contentMove(void *node, int x, int y, int w, int h);
void *contentPanel(void *device, int w, int h, const char *text, unsigned rgb);
void  contentRelease(void *node);

#ifdef __cplusplus
}
#endif

#endif
