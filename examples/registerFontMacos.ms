// Registers a font file the system has not installed and checks CoreText then names its family.
//
//   REGISTER_FONT=<file.ttf> REGISTER_FAMILY=<its family> msc run examples/registerFontMacos.ms

import { findSystemFonts, registerFont, Presentation } from "../src/index";
import { exit, env } from "std/process";

function firstFace(family: string): string {
	const faces = findSystemFonts(0x41 as int32, { presentation: Presentation.Text, weight: 400 as int32, italic: false, family });
	return faces.length > 0 ? faces[0].path : "";
}

function main(): int32 {
	const path = env.get("REGISTER_FONT") ?? "";
	const family = env.get("REGISTER_FAMILY") ?? "";
	if (path == "" || family == "") {
		console.log("registerFontMacos: set REGISTER_FONT and REGISTER_FAMILY");
		return 2;
	}
	let failed = 0;
	const check = (name: string, ok: boolean): void => {
		console.log(`registerFontMacos: ${ok ? "PASS" : "FAIL"} ${name}`);
		if (!ok) failed++;
	};
	check("the family is not installed before", firstFace(family) != path);
	check("registers", registerFont(path).ok);
	check("the family names the file", firstFace(family) == path);
	check("registers again", registerFont(path).ok);
	return failed == 0 ? 0 : 1;
}

exit(main());
