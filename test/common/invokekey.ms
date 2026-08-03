// Tests for src/platform/common/invokekey.{c,h}.
// Compiles the C files directly (no platform deps), tests via extern.

@compile("../../src/platform/common/randombytes.c");
@compile("../../src/platform/common/invokekey.c");
@include("../../src/platform/common/invokekey.h");

// msStringFromCStr is the canonical MS runtime helper (extern declared inline).
extern function msStringFromCStr(cstr: cstring): string;

extern function ion_invoke_key(): cstring;
extern function ion_invoke_key_verify(candidate: cstring): int32;

test "ion_invoke_key returns 64 hex chars" {
	const key = msStringFromCStr(ion_invoke_key());
	assert key.length === 64;
}

test "ion_invoke_key is stable across calls" {
	const a = msStringFromCStr(ion_invoke_key());
	const b = msStringFromCStr(ion_invoke_key());
	assert a === b;
}

test "ion_invoke_key contains only hex chars" {
	const key = msStringFromCStr(ion_invoke_key());
	for (let i = 0; i < key.length; i = i + 1) {
		const c = key.charCodeAt(i);
		const isDigit = c >= 48 && c <= 57;          // '0'-'9'
		const isLowerHex = c >= 97 && c <= 102;      // 'a'-'f'
		assert isDigit || isLowerHex;
	}
}

test "verify accepts the actual key" {
	const key = ion_invoke_key();
	assert ion_invoke_key_verify(key) === 1 as int32;
}

test "verify rejects empty string" {
	assert ion_invoke_key_verify("") === 0 as int32;
}

test "verify rejects wrong key" {
	assert ion_invoke_key_verify("0000000000000000000000000000000000000000000000000000000000000000") === 0 as int32;
}

test "verify rejects partial-match prefix" {
	const key = msStringFromCStr(ion_invoke_key());
	const prefix = key.slice(0 as int64, 32 as int64);
	assert ion_invoke_key_verify(prefix) === 0 as int32;
}

test "verify rejects key + extra chars" {
	const key = msStringFromCStr(ion_invoke_key());
	const extended = `${key}extra`;
	assert ion_invoke_key_verify(extended) === 0 as int32;
}
