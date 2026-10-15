#ifndef ION_EXAMPLE_WINDOW_CONTROLS_H
#define ION_EXAMPLE_WINDOW_CONTROLS_H

#ifdef __cplusplus
extern "C" {
#endif

// Win32 readbacks of ion's main window, for examples/windowControls.ms.
int wcClientX(void);
int wcClientY(void);
int wcClientW(void);
int wcClientH(void);
int wcOuterX(void);
int wcOuterY(void);
int wcDpi(void);
// Device-independent pixels to this window's device pixels, as createWindow does.
int wcScale(int dip);
int wcHasCaption(void);
int wcHasThickFrame(void);
int wcTopmost(void);
int wcVisible(void);
int wcIconic(void);
int wcZoomed(void);
int wcForeground(void);
// Posts WM_CLOSE, as the title-bar close button does.
void wcUserClose(void);
// 1 when the window text equals this UTF-8 string.
int wcTitleIs(const char *utf8);

#ifdef __cplusplus
}
#endif

#endif
