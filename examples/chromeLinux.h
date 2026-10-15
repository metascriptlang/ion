#ifndef ION_EXAMPLE_CHROME_LINUX_H
#define ION_EXAMPLE_CHROME_LINUX_H

// Opens a GtkFileDialog on the window's root, cancels it through a GCancellable after one
// second and logs how it returned and how many toplevels this process had while it was open.
void chromeOpenAndCancel(void *root);
// Logs this process's toplevels other than the window of root, one second from now.
void chromeLogDialogToplevels(void *root);
// 1 when the session bus has a name owner for this service.
int chromeBusHasOwner(const char *name);

#endif
