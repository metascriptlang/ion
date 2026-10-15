// Clipboard without the window host: write a string, read it back, print PASS or FAIL.
//
// Usage:
//   msc build examples/clipboardOnly.ms
//   out/debug/clipboardOnly.exe
import { readClipboardText, writeClipboardText } from "../src/clipboard";
import { exit } from "std/process";

function main(): int32 {
	const sent = "ion clipboard é中文";
	if (!writeClipboardText(sent)) {
		console.log("FAIL: write refused");
		return 1;
	}
	const got = readClipboardText();
	if (got !== sent) {
		console.log(`FAIL: wrote "${sent}" read "${got}"`);
		return 1;
	}
	console.log(`PASS: ${got}`);
	return 0;
}

exit(main());
