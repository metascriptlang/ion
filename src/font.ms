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

when (windows) {
	@compile("./platform/common/noFont.c");
}

when (linux) {
	@compile("./platform/common/noFont.c");
}

import { ionFindSystemFonts, ionSystemFontIndex, ionSystemFontPath } from "./platform/bridge.h";

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
