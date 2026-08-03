// Ion macOS — content protection (block screen capture).
//
// NSWindow.sharingType = NSWindowSharingNone makes the window's pixels
// invisible to screenshot/screen-recording/screen-share APIs. Captured
// frames show black where the window is.
//
// Useful for windows displaying sensitive content (auth tokens, private
// channels, internal links). Off by default.

#import "../state.h"
#import "../../bridge.h"
#include "../../common/windowRegistry.h"

void ionSetContentProtected(int on) {
    ionSetWindowContentProtected(ion_registry_find("main"), on);
}
