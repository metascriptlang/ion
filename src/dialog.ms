// Native dialogs.

import { ionFileOpen, ionMessageBoxAddButton, ionMessageBoxRun } from "./platform/bridge.h";

// Open a native file picker (single-select, any file type). Returns the
// selected absolute path, or "" if the user cancelled.
//
// Blocks the SDL event loop until the user dismisses the dialog. Caller's
// MS code is on the main thread, which is also where the panel must run,
// so this is the natural shape.
export function openFile(): string {
	return ionFileOpen();
}

// Mirror ION_MESSAGE_STYLE_* in bridge.h.
export enum MessageStyle {
	Info,
	Warning,
	Critical,
}

const ION_MESSAGE_BOX_UNSUPPORTED: int32 = -2 as int32;

// An application-modal alert with the buttons' labels in order (one "OK" when empty). Returns the
// pressed button's index, or -1 when it was closed without one. Linux shows no style icon.
export function messageBox(title: string, message: string, buttons: string[], style: MessageStyle): Result<int32, string> {
	if (buttons.length === 0) ionMessageBoxAddButton("OK");
	for (const label of buttons) ionMessageBoxAddButton(label);
	const pressed = ionMessageBoxRun(title, message, style as int32);
	if (pressed === ION_MESSAGE_BOX_UNSUPPORTED) {
		return Result.err("messageBox: not available on Windows until the person chooses between a Common Controls v6 manifest (TaskDialogIndirect, custom labels) and MessageBoxW (fixed button sets); see TODO.md");
	}
	return Result.ok(pressed);
}
