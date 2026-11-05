// Screen reader announcements on the app's active window: NSAccessibility on macOS, a UI
// Automation notification on Windows, GTK's AT-SPI announcement on Linux.
when (macos) {
	@compile("./platform/macos/chrome/announce.m", "-fobjc-arc");
	@passL("-framework Cocoa");
}

when (windows) {
	@compile("./platform/windows/chrome/announce.c");
	@compile("./platform/windows/utf8.c");
	@passL("-luiautomationcore");
	@passL("-loleaut32");
}

when (linux) {
	@compile("./platform/linux/chrome/announce.c");
}

import { ionAnnounce } from "./platform/bridge.h";
import { serviceResult } from "./internal/service";

// Asks the screen reader to speak `text` without moving focus. Ok means the OS took the request,
// not that a screen reader is running.
export function announce(text: string): Result<void, string> {
	return serviceResult("announce", ionAnnounce(text));
}
