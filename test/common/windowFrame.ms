// Tests for src/platform/common/windowFrame.{c,h}: cell-step snapping and fitting a saved frame
// onto the monitors that exist now. Results come back through the ionWindowFrame* record.

@compile("../../src/platform/common/windowFrame.c");
@compile("./windowFrameHelper.c");
@include("../../src/platform/common/windowFrame.h");
@include("../../src/platform/bridge.h");
@include("./windowFrameHelper.h");

extern function ion_resize_snap(size: int32, cell: int32, base: int32): int32;
extern function ionWindowFrameX(): int32;
extern function ionWindowFrameY(): int32;
extern function ionWindowFrameWidth(): int32;
extern function ionWindowFrameHeight(): int32;
extern function wfSizing(x: int32, y: int32, w: int32, h: int32, edges: int32, decoW: int32, decoH: int32,
                         cellW: int32, cellH: int32, baseW: int32, baseH: int32): void;
extern function wfAreasClear(): void;
extern function wfAreaAdd(x: int32, y: int32, w: int32, h: int32): void;
extern function wfFit(x: int32, y: int32, w: int32, h: int32): void;

const LEFT: int32 = 1 as int32;
const RIGHT: int32 = 2 as int32;
const TOP: int32 = 4 as int32;
const BOTTOM: int32 = 8 as int32;

function frame(): string {
	return `${ionWindowFrameX()},${ionWindowFrameY()} ${ionWindowFrameWidth()}x${ionWindowFrameHeight()}`;
}

test "a size snaps to the nearest base plus whole cells" {
	assert ion_resize_snap(100 as int32, 10 as int32, 4 as int32) === 104 as int32;
	assert ion_resize_snap(108 as int32, 10 as int32, 4 as int32) === 104 as int32;
	assert ion_resize_snap(109 as int32, 10 as int32, 4 as int32) === 114 as int32;
	assert ion_resize_snap(114 as int32, 10 as int32, 4 as int32) === 114 as int32;
}

test "a size never snaps below one cell" {
	assert ion_resize_snap(0 as int32, 10 as int32, 4 as int32) === 14 as int32;
	assert ion_resize_snap(-50 as int32, 10 as int32, 4 as int32) === 14 as int32;
}

test "cell 0 leaves the size alone" {
	assert ion_resize_snap(123 as int32, 0 as int32, 4 as int32) === 123 as int32;
}

test "dragging the bottom-right corner moves only the right and bottom edges" {
	// client 203x97 inside a 16x39 frame, cells 9x18 from base 10x8: 10 + 21*9 = 199, 8 + 5*18 = 98
	wfSizing(100 as int32, 50 as int32, 219 as int32, 136 as int32, (RIGHT | BOTTOM) as int32,
	         16 as int32, 39 as int32, 9 as int32, 18 as int32, 10 as int32, 8 as int32);
	assert frame() === "100,50 215x137";
}

test "dragging the top-left corner keeps the bottom-right corner in place" {
	wfSizing(100 as int32, 50 as int32, 219 as int32, 136 as int32, (LEFT | TOP) as int32,
	         16 as int32, 39 as int32, 9 as int32, 18 as int32, 10 as int32, 8 as int32);
	assert frame() === "104,49 215x137";
}

test "dragging one edge snaps only its axis" {
	wfSizing(0 as int32, 0 as int32, 219 as int32, 136 as int32, RIGHT,
	         16 as int32, 39 as int32, 9 as int32, 18 as int32, 10 as int32, 8 as int32);
	assert frame() === "0,0 215x136";
}

test "a frame on a monitor that exists keeps its place" {
	wfAreasClear();
	wfAreaAdd(0 as int32, 0 as int32, 1920 as int32, 1040 as int32);
	wfAreaAdd(1920 as int32, 0 as int32, 2560 as int32, 1400 as int32);
	wfFit(2000 as int32, 100 as int32, 800 as int32, 600 as int32);
	assert frame() === "2000,100 800x600";
}

test "a frame hanging off the edge with its title bar reachable stays where the person put it" {
	wfAreasClear();
	wfAreaAdd(0 as int32, 0 as int32, 1920 as int32, 1040 as int32);
	wfFit(1800 as int32, 900 as int32, 800 as int32, 600 as int32);
	assert frame() === "1800,900 800x600";
}

test "a frame on an unplugged monitor moves onto the primary" {
	wfAreasClear();
	wfAreaAdd(0 as int32, 0 as int32, 1920 as int32, 1040 as int32);
	wfFit(3000 as int32, 100 as int32, 800 as int32, 600 as int32);
	assert frame() === "1120,100 800x600";
}

test "a frame whose title bar is above the work area moves down into it" {
	wfAreasClear();
	wfAreaAdd(0 as int32, 40 as int32, 1920 as int32, 1000 as int32);
	wfFit(100 as int32, 10 as int32, 800 as int32, 600 as int32);
	assert frame() === "100,40 800x600";
}

test "a frame larger than the monitor shrinks to its work area" {
	wfAreasClear();
	wfAreaAdd(0 as int32, 0 as int32, 1280 as int32, 760 as int32);
	wfFit(-200 as int32, -100 as int32, 2000 as int32, 1200 as int32);
	assert frame() === "0,0 1280x760";
}

test "a frame mostly on the second monitor fits that monitor" {
	wfAreasClear();
	wfAreaAdd(0 as int32, 0 as int32, 1920 as int32, 1040 as int32);
	wfAreaAdd(-1280 as int32, 0 as int32, 1280 as int32, 1000 as int32);
	wfFit(-1300 as int32, -50 as int32, 900 as int32, 500 as int32);
	assert frame() === "-1280,0 900x500";
}

test "with no monitor listed the frame is left as saved" {
	wfAreasClear();
	wfFit(5000 as int32, 5000 as int32, 800 as int32, 600 as int32);
	assert frame() === "5000,5000 800x600";
}
