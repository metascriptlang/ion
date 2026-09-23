// Tests for keyCodeFromName — pure MS lookup, no platform deps required by
// the function itself, but importing through the package root pulls in the
// build directives so the test binary links cleanly.

import { keyCodeFromName } from "../src/index";
import { platform } from "std/process";

function native(mac: int32, win: int32, linux: int32): int32 {
	if (platform === "darwin")  return mac;
	if (platform === "windows") return win;
	return linux;
}

test "letter A" {
	assert keyCodeFromName("A") === native(0, 0x41, 0x61);
}

test "letter L" {
	assert keyCodeFromName("L") === native(37, 0x4C, 0x6C);
}

test "letter Z" {
	assert keyCodeFromName("Z") === native(6, 0x5A, 0x7A);
}

test "lowercase letter normalizes to upper" {
	assert keyCodeFromName("l") === native(37, 0x4C, 0x6C);
	assert keyCodeFromName("a") === native(0, 0x41, 0x61);
}

test "digit 0" {
	assert keyCodeFromName("0") === native(29, 0x30, 0x30);
}

test "digit 9" {
	assert keyCodeFromName("9") === native(25, 0x39, 0x39);
}

test "function key F1" {
	assert keyCodeFromName("F1") === native(122, 0x70, 0xFFBE);
}

test "function key F12" {
	assert keyCodeFromName("F12") === native(111, 0x7B, 0xFFC9);
}

test "Space" {
	assert keyCodeFromName("Space") === native(49, 0x20, 0x20);
}

test "Return / Enter alias" {
	assert keyCodeFromName("Return") === native(36, 0x0D, 0xFF0D);
	assert keyCodeFromName("Enter") === native(36, 0x0D, 0xFF0D);
}

test "Escape / Esc alias" {
	assert keyCodeFromName("Escape") === native(53, 0x1B, 0xFF1B);
	assert keyCodeFromName("Esc") === native(53, 0x1B, 0xFF1B);
}

test "Delete / Backspace alias" {
	assert keyCodeFromName("Delete") === native(51, 0x08, 0xFF08);
	assert keyCodeFromName("Backspace") === native(51, 0x08, 0xFF08);
}

test "arrow keys" {
	assert keyCodeFromName("Up") === native(126, 0x26, 0xFF52);
	assert keyCodeFromName("Down") === native(125, 0x28, 0xFF54);
	assert keyCodeFromName("Left") === native(123, 0x25, 0xFF51);
	assert keyCodeFromName("Right") === native(124, 0x27, 0xFF53);
}

test "unknown key name returns -1" {
	assert keyCodeFromName("Foobar") === -1 as int32;
	assert keyCodeFromName("F99") === -1 as int32;
}
