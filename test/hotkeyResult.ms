// Tests for HotkeyResult enum + tryRegisterHotkeyKey unknown-key path.
// (We can't unit-test the live OS Conflict path; that needs a running app.
// SlotsFull is bridge-side, also runtime. Unknown-key is pure MS — testable.)

import { HotkeyResult, tryRegisterHotkeyKey, ModCmd } from "../src/index";

test "HotkeyResult.Ok is 0" {
	assert HotkeyResult.Ok === 0;
}

test "HotkeyResult.UnknownKey is 1" {
	assert HotkeyResult.UnknownKey === 1;
}

test "HotkeyResult.SlotsFull is 2" {
	assert HotkeyResult.SlotsFull === 2;
}

test "HotkeyResult.Conflict is 3" {
	assert HotkeyResult.Conflict === 3;
}

test "tryRegisterHotkeyKey unknown name returns UnknownKey" {
	const r = tryRegisterHotkeyKey(ModCmd, "Foobar", 999 as int32);
	assert r === HotkeyResult.UnknownKey;
}

test "tryRegisterHotkeyKey empty name returns UnknownKey" {
	const r = tryRegisterHotkeyKey(ModCmd, "", 998 as int32);
	assert r === HotkeyResult.UnknownKey;
}
