#ifndef ION_EXAMPLE_SERVICES_WINDOWS_H
#define ION_EXAMPLE_SERVICES_WINDOWS_H

// 1 when keyboard focus is on the window itself, 2 on a child of it (a webview), 0 elsewhere.
int swFocus(int window);
// 1 when the window is the thread's active window.
int swActive(int window);

#endif
