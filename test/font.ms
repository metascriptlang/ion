import { findSystemFont, Presentation, FontRequest } from "../src/font";

const text: FontRequest = { presentation: Presentation.Text, weight: 400 as int32, italic: false, family: "Menlo" };

when (macos) {
	test "a codepoint Menlo lacks is found in STIX Two Math" {
		for (const codepoint of [0x23F5, 0x23FA]) {
			const face = findSystemFont(codepoint as int32, text);
			assert face !== null && face.path.endsWith("/STIXTwoMath.otf");
		}
	}

	test "a codepoint Menlo has is found in Menlo" {
		const face = findSystemFont(0x41 as int32, text);
		assert face !== null && face.path.includes("Menlo");
	}

	test "a face inside a collection names its index" {
		const face = findSystemFont(0x41 as int32, { ...text, weight: 700 as int32 });
		assert face !== null && face.path.endsWith(".ttc") && face.index > (0 as int32);
	}

	test "an emoji presentation is found in Apple Color Emoji" {
		const face = findSystemFont(0x23FA as int32, { ...text, presentation: Presentation.Emoji });
		assert face !== null && face.path.endsWith("/Apple Color Emoji.ttc");
	}
} else {
	test "no backend finds a font" {
		assert findSystemFont(0x41 as int32, text) === null;
	}
}

test "an unassigned codepoint finds no font" {
	assert findSystemFont(0x0378 as int32, text) === null;
}

test "a surrogate or out-of-range codepoint finds no font" {
	assert findSystemFont(0xD800 as int32, text) === null;
	assert findSystemFont(0x110000 as int32, text) === null;
}
