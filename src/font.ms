// An installed font file that draws a codepoint, for a renderer whose own faces lack it.
//
//   const face = findSystemFont(0x23F5, { presentation: Presentation.Text, weight: 400, italic: false, family: "Menlo" });
//   // { path: "/System/Library/Fonts/Supplemental/STIXTwoMath.otf", index: 0 }, or null
//
// macOS asks CoreText (CTFontCreateForString); Windows and Linux find none yet (TODO.md).
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

import { ionFindSystemFont, ionSystemFontIndex } from "./platform/bridge.h";

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

export function findSystemFont(codepoint: int32, request: FontRequest): SystemFont | null {
	const emoji: int32 = request.presentation == Presentation.Emoji ? 1 as int32 : 0 as int32;
	const italic: int32 = request.italic ? 1 as int32 : 0 as int32;
	const path = ionFindSystemFont(codepoint, emoji, request.weight, italic, request.family);
	if (path === "") return null;
	return { path, index: ionSystemFontIndex() };
}
