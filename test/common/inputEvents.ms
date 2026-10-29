// Tests for src/platform/common/inputEvents.{c,h} and keys.{c,h}.
// Pure C — no platform deps. The queue is process-global: each test drains it.

@compile("../../src/platform/common/inputEvents.c");
@compile("../../src/platform/common/keys.c");
@compile("./inputEventsHelper.c");
@include("./inputEventsHelper.h");
@include("../../src/platform/common/inputEvents.h");
@include("../../src/platform/bridge.h");

import { dispatchInput, onPointer, PointerEvent, PointerKind, DeltaMode, KeyMod } from "../../src/input";

extern function ionTestPushPointer(type: int32, window: int32, x: float64, y: float64, p1: float64, p2: float64, mods: int32): int32;
extern function ionTestPushWheel(window: int32, dx: float64, dy: float64, unit: int32): int32;

extern function ion_input_push(type: int32, x: float64, y: float64, p1: float64, p2: float64): int32;
extern function ion_input_next(): int32;
extern function ionInputType(): int32;
extern function ionInputWindow(): int32;
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
	assert ionInputWindow() === -1 as int32;
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

const ModShiftBit: int32 = 1 as int32;
const ModCtrlBit: int32 = 2 as int32;
const ModAltBit: int32 = 4 as int32;

const _seen: PointerEvent[] = [];
onPointer((e: PointerEvent): void => { _seen.push(e); });

// Pushes one pointer record and runs the dispatcher ion's loop runs on it.
// The tests assert that exactly one PointerEvent arrived.
function dispatchPointerRecord(type: int32, mods: int32): void {
	drain();
	_seen.length = 0;
	ionTestPushPointer(type, 3 as int32, 10.0, 20.0, 1.0, 1.0, mods);
	if (ion_input_next() === 1 as int32) dispatchInput(ionInputType());
}

test "a button record pushed with Shift reaches PointerEvent as Shift" {
	dispatchPointerRecord(1 as int32, ModShiftBit);
	assert _seen.length === 1;
	const e = _seen[0];
	assert e.kind === PointerKind.Button;
	assert e.mods.has(KeyMod.Shift);
	assert !e.mods.has(KeyMod.Ctrl);
	assert !e.mods.has(KeyMod.Alt);
}

test "a motion record pushed with Ctrl and Alt reaches PointerEvent as Ctrl and Alt" {
	dispatchPointerRecord(2 as int32, ModCtrlBit | ModAltBit);
	assert _seen.length === 1;
	const e = _seen[0];
	assert e.kind === PointerKind.Motion;
	assert e.mods.has(KeyMod.Ctrl);
	assert e.mods.has(KeyMod.Alt);
	assert !e.mods.has(KeyMod.Shift);
}

test "a pointer record pushed without modifiers reads none" {
	dispatchPointerRecord(3 as int32, 0 as int32);
	assert _seen.length === 1;
	const e = _seen[0];
	assert e.kind === PointerKind.Wheel;
	assert !e.mods.has(KeyMod.Shift);
	assert !e.mods.has(KeyMod.Ctrl);
	assert !e.mods.has(KeyMod.Alt);
}

function dispatchWheel(dx: float64, dy: float64, unit: int32): void {
	drain();
	_seen.length = 0;
	ionTestPushWheel(3 as int32, dx, dy, unit);
	if (ion_input_next() === 1 as int32) dispatchInput(ionInputType());
}

test "a wheel record in notches reaches PointerEvent as lines" {
	dispatchWheel(0.0, -1.0, 1 as int32);
	assert _seen.length === 1;
	const e = _seen[0];
	assert e.kind === PointerKind.Wheel && e.deltaMode === DeltaMode.Line;
	assert e.dx === 0.0 && e.dy === -1.0;
}

test "a precise wheel record reaches PointerEvent as unscaled pixels" {
	dispatchWheel(6.0, -40.0, 0 as int32);
	assert _seen.length === 1;
	const e = _seen[0];
	assert e.kind === PointerKind.Wheel && e.deltaMode === DeltaMode.Pixel;
	assert e.dx === 6.0 && e.dy === -40.0;
}

test "a motion record's movement is in pixels" {
	dispatchPointerRecord(2 as int32, 0 as int32);
	assert _seen.length === 1 && _seen[0].deltaMode === DeltaMode.Pixel;
}

// DOM dispatch clones the listener list (and Node's EventEmitter its array): a handler added
// while an event is being delivered first runs for the next event.
test "a handler registered during dispatch runs from the next event" {
	let added = false;
	let late = 0;
	onPointer((e: PointerEvent): void => {
		if (added) return;
		added = true;
		onPointer((later: PointerEvent): void => { late += 1; });
	});
	dispatchPointerRecord(1 as int32, 0 as int32);
	assert late === 0;
	dispatchPointerRecord(1 as int32, 0 as int32);
	assert late === 1;
}
