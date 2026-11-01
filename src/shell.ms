// Open a URL in the user's default browser / handler app. The Ion
// equivalent of Tauri's @tauri-apps/plugin-shell open(). Used by the OAuth
// loopback flow to launch the provider's consent page.

// Build directives live here too, so a program that only opens URLs links without the window
// host; ipc.ms keeps them for the Linux webview's external-link path.
when (macos) {
	@compile("./platform/macos/core/shell.m", "-fobjc-arc");
	@passL("-framework Cocoa");
}

when (windows) {
	@compile("./platform/windows/core/shell.c");
	@passL("-lshell32");
}

when (linux) {
	@compile("./platform/linux/core/shell.c");
}

import { ionOpenExternal } from "./platform/bridge.h";

// Returns whether the system took the URL: false for an empty or malformed URL or one no
// handler opens, so a caller can reject as React Native's Linking.openURL does. For a scheme
// no app handles, macOS shows its own "no application" alert before returning false.
export function openExternal(url: string): boolean {
	return ionOpenExternal(url) == 1;
}
