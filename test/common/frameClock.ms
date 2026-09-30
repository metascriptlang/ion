// Tests for src/platform/common/frameClock.{c,h}. Surface and window state is
// process-global: each test opens its own surface ids and drains the queue.

@compile("../../src/platform/common/frameClock.c");
@compile("../../src/platform/common/inputEvents.c");
@include("../../src/platform/common/frameClock.h");
@include("../../src/platform/common/inputEvents.h");
@include("../../src/platform/bridge.h");

extern function ion_frame_surface_open(surf: int32, win: int32): void;
extern function ion_frame_surface_close(surf: int32): void;
extern function ion_frame_window_state(win: int32, active: int32, visible: int32): void;
extern function ion_frame_wanted(): int32;
extern function ion_frame_emit(timeMs: float64): int32;
extern function ionRenderSurfaceSetFramePolicy(surf: int32, policy: int32): void;
extern function ionRenderSurfaceSetFrameWhenInactive(surf: int32, enabled: int32): void;
extern function ionRenderSurfaceRequestFrame(surf: int32): void;
extern function ion_input_next(): int32;
extern function ionInputType(): int32;
extern function ionInputSurface(): int32;
extern function ionInputX(): float64;

const OnDemand: int32 = 0 as int32;
const Continuous: int32 = 1 as int32;

function drain(): void {
	while (ion_input_next() === 1 as int32) {}
}

function reset(): void {
	drain();
	for (let i = 0; i < 64; i++) ion_frame_surface_close(i as int32);
	ion_frame_window_state(0 as int32, 1 as int32, 1 as int32);
	ion_frame_window_state(1 as int32, 1 as int32, 1 as int32);
}

test "a new surface is on demand and wants no frame" {
	reset();
	ion_frame_surface_open(0 as int32, 0 as int32);
	assert ion_frame_wanted() === 0 as int32;
	assert ion_frame_emit(1.0) === 0 as int32;
}

test "a request gives exactly one frame record for that surface" {
	reset();
	ion_frame_surface_open(2 as int32, 0 as int32);
	ionRenderSurfaceRequestFrame(2 as int32);
	assert ion_frame_wanted() === 1 as int32;
	assert ion_frame_emit(16.5) === 1 as int32;
	assert ion_input_next() === 1 as int32;
	assert ionInputType() === 9 as int32;
	assert ionInputSurface() === 2 as int32;
	assert ionInputX() === 16.5;
	assert ion_frame_wanted() === 0 as int32;
	assert ion_frame_emit(33.0) === 0 as int32;
}

test "continuous ticks every emit while the window is active" {
	reset();
	ion_frame_surface_open(0 as int32, 0 as int32);
	ionRenderSurfaceSetFramePolicy(0 as int32, Continuous);
	assert ion_frame_emit(1.0) === 1 as int32;
	assert ion_frame_emit(2.0) === 1 as int32;
	ionRenderSurfaceSetFramePolicy(0 as int32, OnDemand);
	assert ion_frame_wanted() === 0 as int32;
}

test "an inactive window stops continuous, not on demand" {
	reset();
	ion_frame_surface_open(0 as int32, 0 as int32);
	ion_frame_surface_open(1 as int32, 0 as int32);
	ionRenderSurfaceSetFramePolicy(0 as int32, Continuous);
	ion_frame_window_state(0 as int32, 0 as int32, 1 as int32);
	assert ion_frame_wanted() === 0 as int32;
	ionRenderSurfaceRequestFrame(1 as int32);
	assert ion_frame_emit(1.0) === 1 as int32;
	assert ion_input_next() === 1 as int32;
	assert ionInputSurface() === 1 as int32;
}

test "FrameWhenInactive keeps continuous ticking while inactive" {
	reset();
	ion_frame_surface_open(0 as int32, 0 as int32);
	ionRenderSurfaceSetFramePolicy(0 as int32, Continuous);
	ionRenderSurfaceSetFrameWhenInactive(0 as int32, 1 as int32);
	ion_frame_window_state(0 as int32, 0 as int32, 1 as int32);
	assert ion_frame_emit(1.0) === 1 as int32;
}

test "a minimized window gets no frame in any mode, and a request waits for restore" {
	reset();
	ion_frame_surface_open(0 as int32, 0 as int32);
	ion_frame_surface_open(1 as int32, 0 as int32);
	ionRenderSurfaceSetFramePolicy(0 as int32, Continuous);
	ionRenderSurfaceSetFrameWhenInactive(0 as int32, 1 as int32);
	ionRenderSurfaceRequestFrame(1 as int32);
	ion_frame_window_state(0 as int32, 0 as int32, 0 as int32);
	assert ion_frame_wanted() === 0 as int32;
	assert ion_frame_emit(1.0) === 0 as int32;
	ion_frame_window_state(0 as int32, 0 as int32, 1 as int32);
	assert ion_frame_emit(2.0) === 2 as int32;
}

test "window state applies per window" {
	reset();
	ion_frame_surface_open(0 as int32, 0 as int32);
	ion_frame_surface_open(1 as int32, 1 as int32);
	ionRenderSurfaceSetFramePolicy(0 as int32, Continuous);
	ionRenderSurfaceSetFramePolicy(1 as int32, Continuous);
	ion_frame_window_state(1 as int32, 0 as int32, 1 as int32);
	assert ion_frame_emit(1.0) === 1 as int32;
	assert ion_input_next() === 1 as int32;
	assert ionInputSurface() === 0 as int32;
}

test "setters on a closed surface are ignored and a reopened id starts fresh" {
	reset();
	ionRenderSurfaceSetFramePolicy(5 as int32, Continuous);
	ionRenderSurfaceRequestFrame(5 as int32);
	assert ion_frame_wanted() === 0 as int32;
	ion_frame_surface_open(5 as int32, 0 as int32);
	ionRenderSurfaceSetFramePolicy(5 as int32, Continuous);
	ion_frame_surface_close(5 as int32);
	ion_frame_surface_open(5 as int32, 0 as int32);
	assert ion_frame_wanted() === 0 as int32;
}
