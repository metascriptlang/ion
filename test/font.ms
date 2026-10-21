import { findSystemFonts, Presentation, FontRequest } from "../src/font";

const text: FontRequest = { presentation: Presentation.Text, weight: 400 as int32, italic: false, family: "Menlo" };

when (macos) {
	test "a codepoint Menlo lacks is found first in STIX Two Math" {
		for (const codepoint of [0x23F5, 0x23FA]) {
			const faces = findSystemFonts(codepoint as int32, text);
			assert faces.length > 0 && faces[0].path.endsWith("/STIXTwoMath.otf");
		}
	}

	test "a codepoint Menlo has is found first in Menlo" {
		const faces = findSystemFonts(0x41 as int32, text);
		assert faces.length > 0 && faces[0].path.includes("Menlo");
	}

	test "a face inside a collection names its index" {
		const faces = findSystemFonts(0x41 as int32, { ...text, weight: 700 as int32 });
		assert faces.length > 0 && faces[0].path.endsWith(".ttc") && faces[0].index > (0 as int32);
	}

	test "a CJK codepoint lists faces past CoreText's answer, each once" {
		for (const weight of [400, 700]) {
			const faces = findSystemFonts(0x4F60 as int32, { ...text, weight: weight as int32 });
			assert faces.length > 1;
			let heiti = false;
			for (let i = 0; i < faces.length; i++) {
				if (faces[i].path.endsWith("/STHeiti Light.ttc") || faces[i].path.endsWith("/STHeiti Medium.ttc")) heiti = true;
				for (let j = i + 1; j < faces.length; j++) {
					assert faces[i].path != faces[j].path || faces[i].index != faces[j].index;
				}
			}
			assert heiti;
		}
	}

	test "an emoji presentation is found first in Apple Color Emoji" {
		const faces = findSystemFonts(0x23FA as int32, { ...text, presentation: Presentation.Emoji });
		assert faces.length > 0 && faces[0].path.endsWith("/Apple Color Emoji.ttc");
	}
} else {
	test "no backend finds a font" {
		assert findSystemFonts(0x41 as int32, text).length == 0;
	}
}

test "an unassigned codepoint finds no font" {
	assert findSystemFonts(0x0378 as int32, text).length == 0;
}

test "a surrogate or out-of-range codepoint finds no font" {
	assert findSystemFonts(0xD800 as int32, text).length == 0;
	assert findSystemFonts(0x110000 as int32, text).length == 0;
}
