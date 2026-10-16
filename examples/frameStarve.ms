// A flood of ionWakeLoop calls, or a setTimeout(f, 0) that re-arms itself, must not
// stop onFrame. Counts frames per 2 s phase on a continuous frame clock:
//   A idle baseline, B wake flood from a native thread, C zero-delay timer chain.
// FAIL: frames in B or C below half of A, or no wakes / timer runs.
// Run with stdout redirected (GUI subsystem): frameStarve.exe > log.txt

import {
	createWindow, defaultOptions, commit, setFramePolicy, FrameContinuous,
	onWake, onFrame, runLoop, closeWindow, Window,
} from "../src/index";
import { exit } from "std/process";

@compile("./frameStarve.c");
@include("./frameStarve.h");

extern function starveNowMs(): int32;
extern function starveSpinUs(us: int32): void;
extern function starveWakeFlood(ms: int32): void;

// Per-run handler work: with none, the flood thread rarely keeps the wake signaled at every wait.
const WORK_US: int32 = 100 as int32;
const PHASE_MS: int32 = 2000 as int32;

let frames = 0;
let wakes = 0;
let timerRuns = 0;
let baseline = 0;
let failures: int32 = 0 as int32;
let chainEnd: int32 = 0 as int32;
let win: Window | null = null;

function report(name: string, ok: boolean, extra: string): void {
	if (!ok) failures = (failures + 1) as int32;
	console.log(`${ok ? "PASS" : "FAIL"} ${name}: frames=${frames} ${extra}`);
	frames = 0;
	wakes = 0;
	timerRuns = 0;
}

function finish(): void {
	console.log(failures === (0 as int32) ? "frameStarve: all PASS" : `frameStarve: ${failures} FAIL`);
	if (win !== null) closeWindow(win);
}

function timerChain(): void {
	timerRuns++;
	starveSpinUs(WORK_US);
	if (starveNowMs() >= chainEnd) {
		report("C timer flood", frames * 2 >= baseline && timerRuns > 0, `timerRuns=${timerRuns}`);
		finish();
		return;
	}
	setTimeout(timerChain, 0);
}

function phaseC(): void {
	chainEnd = (starveNowMs() + PHASE_MS) as int32;
	setTimeout(timerChain, 0);
}

function phaseB(): void {
	starveWakeFlood(PHASE_MS);
	setTimeout((): void => {
		report("B wake flood", frames * 2 >= baseline && wakes > 0, `wakes=${wakes}`);
		phaseC();
	}, PHASE_MS + 200);
}

function main(): int32 {
	const created = createWindow("main", defaultOptions("Ion frame starve", 320 as int32, 200 as int32));
	if (created === null) {
		console.log("frameStarve: no window");
		return 1;
	}
	win = created;
	commit(created);
	setFramePolicy(created, FrameContinuous);
	onFrame((window: int32, timeMs: float64): void => { frames++; });
	onWake((): void => {
		wakes++;
		starveSpinUs(WORK_US);
	});

	setTimeout((): void => {
		frames = 0;
		setTimeout((): void => {
			baseline = frames;
			report("A idle baseline", baseline > 0, "");
			phaseB();
		}, PHASE_MS);
	}, 300);
	runLoop();
	return failures === (0 as int32) ? 0 : 1;
}

exit(main());
