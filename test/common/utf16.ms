// Tests for src/platform/common/utf16.{c,h}: the IME preedit cursor is
// reported in UTF-16 code units, as every MetaScript string index is.

@compile("../../src/platform/common/utf16.c");
@include("../../src/platform/common/utf16.h");

extern function ion_utf16_units(utf8: cstring, chars: int32): int32;

test "ascii is one unit per character" {
	assert ion_utf16_units("abc", 2 as int32) === 2 as int32;
}

test "a Vietnamese prefix is one unit per character, not bytes" {
	// "ế" is three UTF-8 bytes and one UTF-16 unit
	assert ion_utf16_units("tiế", 3 as int32) === 3 as int32;
}

test "a CJK prefix is one unit per character" {
	assert ion_utf16_units("中文x", 2 as int32) === 2 as int32;
}

test "a character above U+FFFF is two units" {
	assert ion_utf16_units("a\u{1F600}b", 2 as int32) === 3 as int32;
	assert ion_utf16_units("a\u{1F600}b", 3 as int32) === 4 as int32;
}

test "the cursor stops at the end of the string" {
	assert ion_utf16_units("ab", 9 as int32) === 2 as int32;
	assert ion_utf16_units("", 1 as int32) === 0 as int32;
}

test "a cursor of zero is zero" {
	assert ion_utf16_units("中", 0 as int32) === 0 as int32;
}
