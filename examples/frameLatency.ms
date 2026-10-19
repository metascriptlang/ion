// Run with stdout redirected (GUI subsystem): frameLatency.exe > log.txt

import {
	createWindow, defaultOptions, commit, setFramePolicy, setFrameWhenInactive, requestFrame,
	FrameOnDemand, FrameContinuous, onFrame, runLoop, closeWindow, Window,
} from "../src/index";
import { exit } from "std/process";

@compile("./frameLatency.c");
@include("./frameLatency.h");

extern function latStamp(): float64;
extern function latRecordSince(phase: int32, t0: float64): void;
extern function latReport(phase: int32): void;

const GAPS_MS: int32[] = [250, 1000, 37];
const TRIALS: int32[] = [40, 20, 40];

let win: Window | null = null;
let phase = 0;
let trial = 0;
let pendingFrom: float64 = 0;
let pending = false;

function startPhase(): void {
	if (phase >= GAPS_MS.length) {
		if (win !== null) closeWindow(win);
		return;
	}
	trial = 0;
	if (win !== null) setFramePolicy(win, phase === 2 ? FrameContinuous : FrameOnDemand);
	setTimeout(request, GAPS_MS[phase]);
}

function request(): void {
	if (win === null) return;
	pendingFrom = latStamp();
	pending = true;
	requestFrame(win);
}

function frameArrived(): void {
	if (!pending) return;
	pending = false;
	latRecordSince(phase as int32, pendingFrom);
	trial++;
	if (trial >= TRIALS[phase]) {
		latReport(phase as int32);
		phase++;
		setTimeout(startPhase, 1500);
		return;
	}
	setTimeout(request, GAPS_MS[phase]);
}

function main(): int32 {
	const created = createWindow("main", defaultOptions("Ion frame latency", 320 as int32, 200 as int32));
	if (created === null) {
		console.log("frameLatency: no window");
		return 1;
	}
	win = created;
	commit(created);
	setFrameWhenInactive(created, true);
	onFrame((window: int32, timeMs: float64): void => { frameArrived(); });
	setTimeout(startPhase, 1500);
	runLoop();
	return 0;
}

exit(main());
