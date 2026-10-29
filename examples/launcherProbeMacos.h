#ifndef ION_EXAMPLE_LAUNCHER_PROBE_MACOS_H
#define ION_EXAMPLE_LAUNCHER_PROBE_MACOS_H

// Localized name of the frontmost application, as the Dock sees it.
const char *lpFrontApp(void);
// Remembers the frontmost app now.
void lpRememberFront(void);
// 1 when the window of `root` is above every on-screen window of the remembered app.
int  lpAboveRemembered(void *root);
// 1 when the window of `root` is on screen.
int  lpOnScreen(void *root);
// 1 when the window of `root` is the key window; 2 when also the app is active.
int  lpKeyState(void *root);
// Posts a key down and up to the HID stream, as the keyboard does (needs Accessibility).
void lpPostKey(int keyCode, int command, int option, int control);
// Starts this executable again with LAUNCHER_ROLE=<role>: the other app.
void lpSpawn(const char *role);
// Clicks the middle of the remembered app's front window through the HID stream.
void lpClickRemembered(void);
// 1 when the remembered app is frontmost.
int  lpRememberedInFront(void);
// 1 when the frontmost app is another process.
int  lpFrontIsOther(void);
// 1 when the window of `root` is on the active Space.
int  lpOnActiveSpace(void *root);
// Experiment knobs: `spaces` adds CanJoinAllSpaces, `aux` also FullScreenAuxiliary, `panel`
// also the non-activating panel style mask (Electron's ElectronNSPanel), floating level.
void lpConfigure(void *root, const char *mode);
// Shows and keys the window of `root` without activating the app (Electron's Focus for a panel).
void lpFocusPanel(void *root);
// 1 when this process may post HID events.
int  lpTrusted(void);

#endif
