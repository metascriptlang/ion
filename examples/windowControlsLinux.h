#ifndef ION_EXAMPLE_WINDOW_CONTROLS_LINUX_H
#define ION_EXAMPLE_WINDOW_CONTROLS_LINUX_H

// GTK4/GDK readbacks of an ion window, for examples/windowControlsLinux.ms.
// wcBind takes the window's compositor root (windowRoot); every other call reads that window.
void wcBind(void *root);
// Client area: the size of the compositor root, which is what createWindow and setSize promise.
int wcRootW(void);
int wcRootH(void);
// 1 when the window title equals this UTF-8 string.
int wcTitleIs(const char *utf8);
int wcVisible(void);
int wcMapped(void);
int wcMinimized(void);
int wcMaximized(void);
int wcDecorated(void);
int wcActive(void);
int wcIsWayland(void);
// Posts the close request the title-bar button posts.
void wcUserClose(void);
// Redirects stderr to a temp file; wcStderrContains stops the capture and reports whether
// the text was written meanwhile.
void wcStderrBegin(void);
int wcStderrContains(const char *needle);

#endif
