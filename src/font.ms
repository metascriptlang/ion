// Installed font files that draw a codepoint, best first, for a renderer whose own faces lack it.
//
//   const faces = findSystemFonts(0x23F5, { presentation: Presentation.Text, weight: 400, italic: false, family: "Menlo" });
//   // [{ path: "/System/Library/Fonts/Supplemental/STIXTwoMath.otf", index: 0 }, …], or []
//
// A face's outline format is not checked: the renderer skips the files it cannot draw. macOS asks
// CoreText; Windows and Linux find none yet (TODO.md).
when (macos) {
	@compile("./platform/macos/core/font.m", "-fobjc-arc");
	@passL("-framework CoreText");
	@passL("-framework Foundation");
}

when (ios) {
	@compile("./platform/macos/core/font.m", "-fobjc-arc");
	@passL("-framework CoreText");
	@passL("-framework Foundation");
}

when (windows) {
	@compile("./platform/common/noFont.c");
	@compile("./platform/windows/core/font.c");
	@compile("./platform/windows/utf8.c");
	@passL("-lgdi32");
}

when (linux) {
	@compile("./platform/common/noFont.c");
	@compile("./platform/linux/core/font.c");
}

import { ionFindSystemFonts, ionSystemFontIndex, ionSystemFontPath, ionRegisterFont } from "./platform/bridge.h";

export enum Presentation { Text, Emoji }

export struct FontRequest {
	presentation: Presentation;
	weight: int32;
	italic: boolean;
	family: string;
}

export struct SystemFont {
	path: string;
	index: int32;
}

export function findSystemFonts(codepoint: int32, request: FontRequest): SystemFont[] {
	const emoji: int32 = request.presentation == Presentation.Emoji ? 1 as int32 : 0 as int32;
	const italic: int32 = request.italic ? 1 as int32 : 0 as int32;
	const count = ionFindSystemFonts(codepoint, emoji, request.weight, italic, request.family);
	let faces: SystemFont[] = [];
	for (let i: int32 = 0; i < count; i++) {
		faces.push({ path: ionSystemFontPath(i), index: ionSystemFontIndex(i) });
	}
	return faces;
}

// Makes the faces of a font file the app ships (`Target.assets`) nameable by the platform text stack,
// UIKit's `UIFont fontWithName:` and AppKit's `NSFont fontWithName:` included, for this process:
//
//   registerFont(join(resourcePath(), "fonts/Inter.ttf"));
//
// Registering the same file again succeeds. macOS and iOS register through CoreText, Windows as a
// private GDI font; Linux refuses every file yet (TODO.md).
export function registerFont(path: string): Result<void, string> {
	if (ionRegisterFont(path) == 1) return Result.ok(null);
	return Result.err("cannot register font " + path);
}
