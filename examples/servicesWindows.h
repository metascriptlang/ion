#ifndef ION_EXAMPLE_SERVICES_WINDOWS_H
#define ION_EXAMPLE_SERVICES_WINDOWS_H

// 1 when keyboard focus is on the window itself, 2 on a child of it (a webview), 0 elsewhere.
int swFocus(int window);
// 1 when the window is the thread's active window.
int swActive(int window);
// 1 when the exe's RT_MANIFEST resource 1 names Microsoft.Windows.Common-Controls.
int swManifestNamesCommonControls(void);
// The loaded comctl32's major version (DllGetVersion), 0 when it exports no TaskDialogIndirect.
int swTaskDialogComctlMajor(void);
// Every ms, up to 50 times, look for this thread's task dialog, then press the button with that id
// (TDM_CLICK_BUTTON) or close it (WM_CLOSE) when id is 0; swDialogSeen() names its class and title.
void swAnswerDialogAfter(int ms, int id);
const char *swDialogSeen(void);

#endif
