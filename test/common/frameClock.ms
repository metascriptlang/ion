// Tests for src/platform/common/frameClock.{c,h}. Window state is
// process-global: each test opens its own window ids and drains the queue.

@compile("../../src/platform/common/frameClock.c");
@compile("../../src/platform/common/inputEvents.c");
@include("../../src/platform/common/frameClock.h");
@include("../../src/platform/common/inputEvents.h");
@include("../../src/platform/bridge.h");

extern function ion_frame_window_open(win: int32): void;
extern function ion_frame_window_close(win: int32): void;
extern function ion_frame_window_state(win: int32, active: int32, visible: int32): void;
extern function ion_frame_wanted(): int32;
extern function ion_frame_emit(timeMs: float64): int32;
extern function ion_frame_pacing_window(): int32;
extern function ionWindowSetFramePolicy(win: int32, policy: int32): void;
extern function ionWindowSetFrameWhenInactive(win: int32, enabled: int32): void;
extern function ionWindowRequestFrame(win: int32): void;
extern function ion_input_next(): int32;
extern function ionInputType(): int32;
extern function ionInputWindow(): int32;
extern function ionInputX(): float64;

const OnDemand: int32 = 0 as int32;
const Continuous: int32 = 1 as int32;

function drain(): void {
	while (ion_input_next() === 1 as int32) {}
}

function reset(): void {
	drain();
	for (let i = 0; i < 16; i++) ion_frame_window_close(i as int32);
}

test "a new window is on demand and wants no frame" {
	reset();
	ion_frame_window_open(0 as int32);
	assert ion_frame_wanted() === 0 as int32;
	assert ion_frame_emit(1.0) === 0 as int32;
}

test "a request gives exactly one frame record for that window" {
	reset();
	ion_frame_window_open(2 as int32);
	ionWindowRequestFrame(2 as int32);
	assert ion_frame_wanted() === 1 as int32;
	assert ion_frame_emit(16.5) === 1 as int32;
	assert ion_input_next() === 1 as int32;
	assert ionInputType() === 9 as int32;
	assert ionInputWindow() === 2 as int32;
	assert ionInputX() === 16.5;
	assert ion_frame_wanted() === 0 as int32;
	assert ion_frame_emit(33.0) === 0 as int32;
}

test "continuous ticks every emit while the window is active" {
	reset();
	ion_frame_window_open(0 as int32);
	ionWindowSetFramePolicy(0 as int32, Continuous);
	assert ion_frame_emit(1.0) === 1 as int32;
	assert ion_frame_emit(2.0) === 1 as int32;
	ionWindowSetFramePolicy(0 as int32, OnDemand);
	assert ion_frame_wanted() === 0 as int32;
}

test "an inactive window stops continuous, not a request" {
	reset();
	ion_frame_window_open(0 as int32);
	ionWindowSetFramePolicy(0 as int32, Continuous);
	ion_frame_window_state(0 as int32, 0 as int32, 1 as int32);
	assert ion_frame_wanted() === 0 as int32;
	ionWindowRequestFrame(0 as int32);
	assert ion_frame_emit(1.0) === 1 as int32;
	assert ion_frame_emit(2.0) === 0 as int32;
}

test "FrameWhenInactive keeps continuous ticking while inactive" {
	reset();
	ion_frame_window_open(0 as int32);
	ionWindowSetFramePolicy(0 as int32, Continuous);
	ionWindowSetFrameWhenInactive(0 as int32, 1 as int32);
	ion_frame_window_state(0 as int32, 0 as int32, 1 as int32);
	assert ion_frame_emit(1.0) === 1 as int32;
}

test "a minimized window gets no frame in any mode, and a request waits for restore" {
	reset();
	ion_frame_window_open(0 as int32);
	ion_frame_window_open(1 as int32);
	ionWindowSetFramePolicy(0 as int32, Continuous);
	ionWindowSetFrameWhenInactive(0 as int32, 1 as int32);
	ionWindowRequestFrame(1 as int32);
	ion_frame_window_state(0 as int32, 0 as int32, 0 as int32);
	ion_frame_window_state(1 as int32, 1 as int32, 0 as int32);
	assert ion_frame_wanted() === 0 as int32;
	assert ion_frame_emit(1.0) === 0 as int32;
	ion_frame_window_state(0 as int32, 0 as int32, 1 as int32);
	ion_frame_window_state(1 as int32, 1 as int32, 1 as int32);
	assert ion_frame_emit(2.0) === 2 as int32;
}

test "window state applies per window" {
	reset();
	ion_frame_window_open(0 as int32);
	ion_frame_window_open(1 as int32);
	ionWindowSetFramePolicy(0 as int32, Continuous);
	ionWindowSetFramePolicy(1 as int32, Continuous);
	ion_frame_window_state(1 as int32, 0 as int32, 1 as int32);
	assert ion_frame_emit(1.0) === 1 as int32;
	assert ion_input_next() === 1 as int32;
	assert ionInputWindow() === 0 as int32;
}

test "setters on a closed window are ignored and a reopened id starts fresh" {
	reset();
	ionWindowSetFramePolicy(5 as int32, Continuous);
	ionWindowRequestFrame(5 as int32);
	ion_frame_window_state(5 as int32, 0 as int32, 0 as int32);
	assert ion_frame_wanted() === 0 as int32;
	ion_frame_window_open(5 as int32);
	ionWindowSetFramePolicy(5 as int32, Continuous);
	ion_frame_window_close(5 as int32);
	ion_frame_window_open(5 as int32);
	assert ion_frame_wanted() === 0 as int32;
}

test "the pacing window is the last requester while due, else the first due window" {
	reset();
	ion_frame_window_open(0 as int32);
	ion_frame_window_open(1 as int32);
	assert ion_frame_pacing_window() === -1 as int32;
	ionWindowSetFramePolicy(0 as int32, Continuous);
	ionWindowRequestFrame(1 as int32);
	assert ion_frame_pacing_window() === 1 as int32;
	assert ion_frame_emit(1.0) === 2 as int32;
	assert ion_frame_pacing_window() === 0 as int32;
}
