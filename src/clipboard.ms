// Text clipboard. UTF-8 at this surface; the OS formats are CF_UNICODETEXT
// (Windows), NSPasteboard string (macOS) and the GTK CLIPBOARD selection (Linux).

// Build directives live here: a program that only uses the clipboard must not pull in the
// window host. The Windows source needs utf8.c; the Linux source includes only GTK.
when (windows) {
	@compile("./platform/windows/chrome/clipboard.c");
	@compile("./platform/windows/utf8.c");
	@passL("-luser32");
}

when (macos) {
	@compile("./platform/macos/chrome/clipboard.m", "-fobjc-arc");
	@passL("-framework Cocoa");
}

when (linux) {
	const gtkCflags = @comptime {
		const r = exec("pkg-config --cflags gtk4");
		if (!r.ok) return "";
		return r.value.trim();
	};
	const gtkLibs = @comptime {
		const r = exec("pkg-config --libs gtk4");
		if (!r.ok) return "";
		return r.value.trim();
	};
	@compile("./platform/linux/chrome/clipboard.c");
	@passC(gtkCflags);
	@passL(gtkLibs);
}

import { exec } from "std/process";
import { ionClipboardRead, ionClipboardWrite } from "./platform/bridge.h";

// The clipboard's text, or "" when it holds no text or could not be opened.
export function readClipboardText(): string {
	return ionClipboardRead();
}

// Replaces the clipboard with `text`. False when the OS refused the write.
export function writeClipboardText(text: string): boolean {
	return ionClipboardWrite(text) === 1;
}
