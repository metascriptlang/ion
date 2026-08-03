// Ion Windows — content protection (block screen capture).
//
// SetWindowDisplayAffinity(hwnd, WDA_EXCLUDEFROMCAPTURE) is the Windows
// equivalent of NSWindow.sharingType = NSWindowSharingNone on macOS.
// Available since Win10 2004 (build 19041). On older builds the call
// silently fails and the window remains capturable — accept that for v0.

#include "../state.h"
#include "../../bridge.h"

#ifndef WDA_EXCLUDEFROMCAPTURE
#define WDA_EXCLUDEFROMCAPTURE 0x00000011
#endif

#ifndef WDA_NONE
#define WDA_NONE 0x00000000
#endif

void ionSetContentProtected(int on) {
    if (s_mainHwnd == NULL) return;
    SetWindowDisplayAffinity(s_mainHwnd, on ? WDA_EXCLUDEFROMCAPTURE : WDA_NONE);
}
