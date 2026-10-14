// Text clipboard. UTF-8 at this surface; the OS formats are CF_UNICODETEXT
// (Windows), NSPasteboard string (macOS) and the GTK CLIPBOARD selection (Linux).

import { ionClipboardRead, ionClipboardWrite } from "./platform/bridge.h";

// The clipboard's text, or "" when it holds no text or could not be opened.
export function readClipboardText(): string {
	return ionClipboardRead();
}

// Replaces the clipboard with `text`. False when the OS refused the write.
export function writeClipboardText(text: string): boolean {
	return ionClipboardWrite(text) === 1;
}
