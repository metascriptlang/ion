#ifndef ION_EXAMPLE_WINDOW_PROBE_WINDOWS_H
#define ION_EXAMPLE_WINDOW_PROBE_WINDOWS_H

// The title-bar close button's and the system menu's path: WM_SYSCOMMAND SC_CLOSE sent to the window.
void wpSysClose(int window);
// Alt+F4 as the window proc receives it: WM_SYSKEYDOWN VK_F4 with the Alt bit, then its WM_SYSKEYUP;
// DefWindowProc posts WM_SYSCOMMAND SC_CLOSE, which the loop delivers.
void wpAltF4(int window);
// A real left click on the close button through SendInput, the cursor put back afterwards.
// 1 when the button's centre is on this window and the input was injected, else 0.
int wpClickClose(int window);
// 1 when the window is the thread's active window, 2 when it is minimized, else 0.
int wpWindowState(int window);
// Registers a hidden top-level window for shell hook messages; wpFlashes counts HSHELL_FLASH for a window.
int wpWatchFlashes(void);
int wpFlashes(int window);
// Installs (or removes) a WM_GETOBJECT hook through ionWindowSetAutomation that answers UiaRootObjectId
// with 0x5157 and declines every other object id.
void wpInstallAutomation(int window);
void wpRemoveAutomation(int window);
// Sends WM_GETOBJECT with that object id: 1 when the hook's 0x5157 came back, 2 another nonzero LRESULT, 0 zero.
int wpGetObject(int window, int objectId);
int wpHookCalls(void);
// 1 when the last hook call carried this window's HWND and objectId.
int wpHookSaw(int window, int objectId);
int wpDisconnects(void);
// Remembers the window's HWND now, so wpDisconnectedRemembered can tell after it is destroyed.
void wpRemember(int window);
int wpDisconnectedRemembered(void);

#endif
