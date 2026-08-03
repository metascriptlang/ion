// Tests for keyCodeFromName — pure MS lookup, no platform deps required by
// the function itself, but importing through the package root pulls in the
// build directives so the test binary links cleanly.

import { keyCodeFromName } from "../src/index";

test "letter A → 0" {
	assert keyCodeFromName("A") === 0 as int32;
}

test "letter L → 37" {
	assert keyCodeFromName("L") === 37 as int32;
}

test "letter Z → 6" {
	assert keyCodeFromName("Z") === 6 as int32;
}

test "lowercase letter normalizes to upper" {
	assert keyCodeFromName("l") === 37 as int32;
	assert keyCodeFromName("a") === 0 as int32;
}

test "digit 0 → 29" {
	assert keyCodeFromName("0") === 29 as int32;
}

test "digit 9 → 25" {
	assert keyCodeFromName("9") === 25 as int32;
}

test "function key F1 → 122" {
	assert keyCodeFromName("F1") === 122 as int32;
}

test "function key F12 → 111" {
	assert keyCodeFromName("F12") === 111 as int32;
}

test "Space → 49" {
	assert keyCodeFromName("Space") === 49 as int32;
}

test "Return / Enter alias → 36" {
	assert keyCodeFromName("Return") === 36 as int32;
	assert keyCodeFromName("Enter") === 36 as int32;
}

test "Escape / Esc alias → 53" {
	assert keyCodeFromName("Escape") === 53 as int32;
	assert keyCodeFromName("Esc") === 53 as int32;
}

test "Delete / Backspace alias → 51" {
	assert keyCodeFromName("Delete") === 51 as int32;
	assert keyCodeFromName("Backspace") === 51 as int32;
}

test "arrow keys" {
	assert keyCodeFromName("Up") === 126 as int32;
	assert keyCodeFromName("Down") === 125 as int32;
	assert keyCodeFromName("Left") === 123 as int32;
	assert keyCodeFromName("Right") === 124 as int32;
}

test "unknown key name returns -1" {
	assert keyCodeFromName("Foobar") === -1 as int32;
	assert keyCodeFromName("F99") === -1 as int32;
}

test "empty string returns -1" {
	assert keyCodeFromName("") === -1 as int32;
}
