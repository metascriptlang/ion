// Native dialogs.

import { ionFileOpen } from "./platform/bridge.h";

// Open a native file picker (single-select, any file type). Returns the
// selected absolute path, or "" if the user cancelled.
//
// Blocks the SDL event loop until the user dismisses the dialog. Caller's
// MS code is on the main thread, which is also where the panel must run,
// so this is the natural shape.
export function openFile(): string {
	return ionFileOpen();
}
