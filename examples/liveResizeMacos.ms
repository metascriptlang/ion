// macOS live resize: while AppKit's tracking loop runs a window resize, Ion must keep running
// msc's timers, frames and resize records (webview/poll.m ionMacModalPump), the counterpart of
// modalLoop.ms for the Win32 move/size loop. A 2 s control, then a corner drag posted to the
// app's own event queue; the drag passes when its interval and frame rates reach a quarter of
// the control's and at least one resized event arrives during it.
// Run: msc build examples/liveResizeMacos.ms && out/debug/liveResizeMacos

import {
	createWindow, defaultOptions, commit, setFramePolicy, setFrameWhenInactive, FrameContinuous,
	onFrame, onWindowEvent, runLoop, closeWindow, windowRoot, WindowEventResized, Window,
} from "../src/index";
import { exit } from "std/process";

when (macos) {
	@compile("./liveResizeMacos.m", "-fobjc-arc");
}
@include("./liveResizeMacos.h");

extern function lrBind(root: Ptr<void>): void;
extern function lrCount(kind: int32): void;
extern function lrRun(scenario: int32): void;
extern function lrDone(): int32;
extern function lrFailures(): int32;

const SCENARIOS: int32[] = [0, 1];
let next = 0;
let win: Window | null = null;

function step(): void {
	if (next >= SCENARIOS.length) {
		console.log(`liveResizeMacos: done, ${lrFailures()} failed`);
		if (win !== null) closeWindow(win);
		return;
	}
	lrRun(SCENARIOS[next]);
	next++;
	setTimeout(waitDone, 200);
}

function waitDone(): void {
	if (lrDone() === (0 as int32)) {
		setTimeout(waitDone, 100);
		return;
	}
	setTimeout(step, 500);
}

function main(): int32 {
	const created = createWindow("main", defaultOptions("Ion live resize probe", 480 as int32, 300 as int32));
	if (created === null) {
		console.log("liveResizeMacos: no window");
		return 1;
	}
	const own: Window = created;
	win = own;
	commit(own);
	lrBind(windowRoot(own));
	setFramePolicy(own, FrameContinuous);
	setFrameWhenInactive(own, true);
	onFrame((window: int32, timeMs: float64): void => { lrCount(0 as int32); });
	onWindowEvent((label: string, eventType: int32): void => {
		if (eventType === WindowEventResized) lrCount(2 as int32);
	});
	setInterval((): void => { lrCount(1 as int32); }, 10);
	setTimeout(step, 500);
	runLoop();
	return lrFailures() === (0 as int32) ? 0 : 1;
}

exit(main());
