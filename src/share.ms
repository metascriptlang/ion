// The OS share picker on the app's active window: NSSharingServicePicker on macOS,
// DataTransferManager on Windows 10 and later. Linux has none (TODO.md).
when (macos) {
	@compile("./platform/macos/chrome/share.m", "-fobjc-arc");
	@passL("-framework Cocoa");
}

when (windows) {
	@compile("./platform/windows/chrome/share.cpp");
	@compile("./platform/windows/utf8.c");
	@passL("-lole32");
	@passL("-luuid");
}

when (linux) {
	@compile("./platform/linux/chrome/share.c");
}

import { ionShare } from "./platform/bridge.h";
import { serviceResult } from "./internal/service";

// Offers `text` and `url` ("" leaves either out) with `title` as the subject, and returns once the
// picker is shown; what the person picks is not reported.
export function share(title: string, text: string, url: string): Result<void, string> {
	if (text === "" && url === "") return Result.err("share: nothing to share, text and url are both empty");
	return serviceResult("share", ionShare(title, text, url));
}
