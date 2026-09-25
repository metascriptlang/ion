// Tests for src/platform/common/inputEvents.{c,h} and keys.{c,h}.
// Pure C — no platform deps. The queue is process-global: each test drains it.

@compile("../../src/platform/common/inputEvents.c");
@compile("../../src/platform/common/keys.c");
@include("../../src/platform/common/inputEvents.h");
@include("../../src/platform/bridge.h");

extern function ion_input_push(type: int32, x: float64, y: float64, p1: float64, p2: float64): int32;
extern function ion_input_next(): int32;
extern function ionInputType(): int32;
extern function ionInputSurface(): int32;
extern function ionInputX(): float64;
extern function ionInputP1(): float64;
extern function ionInputP2(): float64;
extern function ionInputText(): string;
extern function ionKeyName(key: int32): string;

function drain(): void {
	while (ion_input_next() === 1 as int32) {}
}

test "next on an empty queue returns 0" {
	drain();
	assert ion_input_next() === 0 as int32;
}

test "records come out in push order" {
	drain();
	ion_input_push(1 as int32, 0.25, 0.5, 1.0, 1.0);
	ion_input_push(3 as int32, 0.75, 0.5, 0.0, -1.0);
	assert ion_input_next() === 1 as int32;
	assert ionInputType() === 1 as int32;
	assert ionInputX() === 0.25;
	assert ion_input_next() === 1 as int32;
	assert ionInputType() === 3 as int32;
	assert ionInputP2() === -1.0;
	assert ion_input_next() === 0 as int32;
}

test "a pointer shorthand record has no surface and no text" {
	drain();
	ion_input_push(2 as int32, 0.1, 0.2, 0.01, 0.02);
	assert ion_input_next() === 1 as int32;
	assert ionInputSurface() === -1 as int32;
	assert ionInputText() === "";
}

test "overflow drops the oldest record" {
	drain();
	for (let i = 0; i < 257; i++) {
		ion_input_push(1 as int32, 0.0, 0.0, i as float64, 0.0);
	}
	assert ion_input_next() === 1 as int32;
	assert ionInputP1() === 1.0;
	drain();
}

test "key names follow W3C KeyboardEvent.code" {
	assert ionKeyName(0 as int32) === "Unidentified";
	assert ionKeyName(20 as int32) === "KeyA";
	assert ionKeyName(102 as int32) === "NumpadEnter";
	assert ionKeyName(126 as int32) === "F1";
}

test "an out-of-range key has no name" {
	assert ionKeyName(-1 as int32) === "";
	assert ionKeyName(182 as int32) === "";
}
