// Tests for modifier flag constants.

import { ModCmd, ModShift, ModAlt, ModCtrl } from "../src/mods";

test "ModCmd is 1" {
	assert ModCmd === 1 as int32;
}

test "ModShift is 2" {
	assert ModShift === 2 as int32;
}

test "ModAlt is 4" {
	assert ModAlt === 4 as int32;
}

test "ModCtrl is 8" {
	assert ModCtrl === 8 as int32;
}

test "all flags are distinct bits (bitwise OR sums to 15)" {
	const all: int32 = ModCmd | ModShift | ModAlt | ModCtrl;
	assert all === 15 as int32;
}

test "Cmd+Shift composes to 3" {
	assert (ModCmd | ModShift) === 3 as int32;
}

test "Cmd+Alt composes to 5" {
	assert (ModCmd | ModAlt) === 5 as int32;
}

test "no flag overlaps another" {
	assert (ModCmd & ModShift) === 0 as int32;
	assert (ModCmd & ModAlt) === 0 as int32;
	assert (ModCmd & ModCtrl) === 0 as int32;
	assert (ModShift & ModAlt) === 0 as int32;
	assert (ModShift & ModCtrl) === 0 as int32;
	assert (ModAlt & ModCtrl) === 0 as int32;
}
