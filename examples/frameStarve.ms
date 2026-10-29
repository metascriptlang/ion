// A flood of ionWakeLoop calls, or a setTimeout(f, 0) that re-arms itself, must not
// stop onFrame. Counts frames per 2 s phase on a continuous frame clock:
//   A idle baseline, B wake flood from a native thread, C zero-delay timer chain and D the same
//   chain beside a wake flood, each of C and D once per handler work level in LEVELS_US, and
//   E a wake every 50 ms while each frame's work outlasts the display interval, so a frame is
//   due on every turn (Haro's cursor animating while someone types).
// FAIL: frames in B or C below half of A, no wakes / timer runs, or a wake in E taken more than
//   50 ms after it was made.
// Run with stdout redirected (GUI subsystem): frameStarve.exe > log.txt

import {
	createWindow, defaultOptions, commit, setFramePolicy, setFrameWhenInactive, FrameContinuous,
	onWake, onFrame, runLoop, closeWindow, Window,
} from "../src/index";
import { exit } from "std/process";

@compile("./frameStarve.c");
@include("./frameStarve.h");

extern function starveNowMs(): int32;
extern function starveSpinUs(us: int32): void;
extern function starveWakeFlood(ms: int32): void;
extern function starveWakeEvery(periodMs: int32, ms: int32): void;
extern function starveTakeWakeAgeMs(): int32;

// Per-run handler work of the timer chain, one phase pair per level. 100 us is the first
// measurement (2026-10-17); 2, 8 and 20 ms cross the GetTickCount64 step (about 15.6 ms), at
// which a due msc deadline is already due on every entry to ionPollEvent.
const LEVELS_US: int32[] = [100, 2000, 8000, 20000];
// Per-run wake handler work: with none, the flood thread rarely keeps the wake signaled at every wait.
const WAKE_US: int32 = 100 as int32;
const PHASE_MS: int32 = 2000 as int32;
// Frame work in E: longer than one interval at 60 Hz, so the next tick is already due.
const BUSY_FRAME_US: int32 = 20000 as int32;
const LATE_WAKE_MS: int32 = 50 as int32;

let frames = 0;
let wakes = 0;
let timerRuns = 0;
let baseline = 0;
let failures: int32 = 0 as int32;
let chainStart: int32 = 0 as int32;
let chainEnd: int32 = 0 as int32;
let workUs: int32 = 0 as int32;
let levelIndex = 0;
let withWake = false;
let busyFrames = false;
let maxWakeAgeMs: int32 = 0 as int32;
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

function startPhase(): void {
	workUs = LEVELS_US[levelIndex];
	chainStart = starveNowMs();
	chainEnd = (chainStart + PHASE_MS) as int32;
	if (withWake) starveWakeFlood(PHASE_MS);
	setTimeout(timerChain, 0);
}

function endPhase(): void {
	const elapsed = starveNowMs() - chainStart;
	const name = `${withWake ? "D timer+wake" : "C timer"} work=${workUs}us elapsedMs=${elapsed}`;
	report(name, frames * 2 >= baseline && timerRuns > 0 && (!withWake || wakes > 0), `timerRuns=${timerRuns} wakes=${wakes}`);
	if (!withWake) {
		withWake = true;
	} else if (levelIndex + 1 < LEVELS_US.length) {
		withWake = false;
		levelIndex++;
	} else {
		phaseE();
		return;
	}
	startPhase();
}

function timerChain(): void {
	timerRuns++;
	starveSpinUs(workUs);
	if (starveNowMs() >= chainEnd) {
		endPhase();
		return;
	}
	setTimeout(timerChain, 0);
}

function phaseE(): void {
	busyFrames = true;
	maxWakeAgeMs = 0 as int32;
	starveWakeEvery(LATE_WAKE_MS, PHASE_MS);
	setTimeout((): void => {
		busyFrames = false;
		report("E wake beside busy frames", frames > 0 && wakes > 0 && maxWakeAgeMs <= LATE_WAKE_MS,
			`wakes=${wakes} maxWakeAgeMs=${maxWakeAgeMs}`);
		finish();
	}, PHASE_MS + 200);
}

function phaseB(): void {
	starveWakeFlood(PHASE_MS);
	setTimeout((): void => {
		report("B wake flood", frames * 2 >= baseline && wakes > 0, `wakes=${wakes}`);
		startPhase();
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
	setFrameWhenInactive(created, true);
	onFrame((window: int32, timeMs: float64): void => {
		frames++;
		if (busyFrames) starveSpinUs(BUSY_FRAME_US);
	});
	onWake((): void => {
		wakes++;
		const age = starveTakeWakeAgeMs();
		if (age > maxWakeAgeMs) maxWakeAgeMs = age;
		starveSpinUs(WAKE_US);
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
