#ifndef ION_EXAMPLE_WINDOW_CONTROLS_MACOS_H
#define ION_EXAMPLE_WINDOW_CONTROLS_MACOS_H

// AppKit readbacks of an ion window, for examples/windowControlsMacos.ms.
// wcBind takes the window's compositor root (windowRoot, the contentView); every other call
// reads that view's window.
void wcBind(void *root);
// Client area in points: the size of the content view, which createWindow and setSize promise.
int wcRootW(void);
int wcRootH(void);
// Outer frame top-left in points, origin at the top-left of the primary screen.
int wcOuterX(void);
int wcOuterY(void);
// 1 when the window title equals this UTF-8 string.
int wcTitleIs(const char *utf8);
int wcVisible(void);
int wcMinimized(void);
int wcMaximized(void);
int wcDecorated(void);
int wcTopmost(void);
int wcActive(void);
// Clicks the title-bar close button (performClose:).
void wcUserClose(void);

#endif
