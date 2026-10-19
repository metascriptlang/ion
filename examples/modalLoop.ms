// The modal loop warps the pointer to the window; the helper restores it afterwards.
// Run with stdout redirected (GUI subsystem): modalLoop.exe > log.txt

import {
	createWindow, defaultOptions, commit, setFramePolicy, setFrameWhenInactive, FrameContinuous,
	onWake, onFrame, runLoop, closeWindow, Window,
} from "../src/index";
import { exit } from "std/process";

@compile("./modalLoop.c");
@include("./modalLoop.h");

extern function modalInit(): int32;
extern function modalCount(kind: int32): void;
extern function modalRun(scenario: int32): void;
extern function modalDone(): int32;

const SCENARIOS: int32[] = [0, 1, 0, 2];
let next = 0;
let win: Window | null = null;

function step(): void {
	if (next >= SCENARIOS.length) {
		console.log("modalLoop: done");
		if (win !== null) closeWindow(win);
		return;
	}
	modalRun(SCENARIOS[next]);
	next++;
	setTimeout(waitDone, 200);
}

function waitDone(): void {
	if (modalDone() === (0 as int32)) {
		setTimeout(waitDone, 100);
		return;
	}
	setTimeout(step, 500);
}

function main(): int32 {
	const created = createWindow("main", defaultOptions("Ion modal loop probe", 480 as int32, 300 as int32));
	if (created === null) {
		console.log("modalLoop: no window");
		return 1;
	}
	const own: Window = created;
	win = own;
	commit(own);
	setFramePolicy(own, FrameContinuous);
	setFrameWhenInactive(own, true);
	onFrame((window: int32, timeMs: float64): void => { modalCount(0 as int32); });
	onWake((): void => { modalCount(2 as int32); });
	setInterval((): void => { modalCount(1 as int32); }, 10);
	setTimeout((): void => {
		if (modalInit() === (0 as int32)) {
			console.log("modalLoop: window not found by title");
			closeWindow(own);
			return;
		}
		step();
	}, 500);
	runLoop();
	return 0;
}

exit(main());
