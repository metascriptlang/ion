// Window security toggles.

import { ionSetContentProtected } from "./platform/bridge.h";

// Toggle content protection on the main window. When enabled, screen
// capture (screenshots, screen recordings, screen sharing) cannot read
// the window's pixels — captured frames show black.
//
// Useful for windows displaying sensitive content (auth tokens, internal
// links, private Cubes). Off by default.
export function setContentProtected(on: boolean): void {
	ionSetContentProtected(on ? 1 as int32 : 0 as int32);
}
