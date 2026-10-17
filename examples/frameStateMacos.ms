// macOS frame clock per window state, the table in docs/WINDOW-CONTENT.md "Frame clock":
// a continuous window ticks while active, stops when minimized, hidden, inactive (unless
// setFrameWhenInactive) or covered by another window, and resumes after each.
// Counts onFrame for window "a" in 1 s phases.
// Run: msc build examples/frameStateMacos.ms && out/debug/frameStateMacos

import {
	createWindow, defaultOptions, setFramePolicy, setFrameWhenInactive, FrameContinuous,
	onFrame, runLoop, closeWindow, focus, minimize, hide, show, setSize, setPosition, Window,
} from "../src/index";
import { exit } from "std/process";

const PHASE_MS = 1000;
let frames = 0;
let failures = 0;

function report(name: string, ok: boolean): void {
	if (!ok) failures += 1;
	console.log(`${ok ? "PASS" : "FAIL"} ${name}: frames=${frames}`);
}

function main(): int32 {
	const ca = createWindow("a", defaultOptions("frame state a", 320 as int32, 200 as int32));
	if (ca === null) return 1;
	const a: Window = ca;
	setPosition(a, 100 as int32, 100 as int32);
	setFramePolicy(a, FrameContinuous);
	let b: Window | null = null;
	onFrame((window: int32, timeMs: float64): void => { if (window === a.id) frames++; });

	// Each phase acts, lets the state settle for 300 ms, then counts for PHASE_MS.
	const phases: string[] = ["active", "minimized", "restored", "hidden", "shown", "other window active",
		"other window active, FrameWhenInactive", "covered by the other window", "uncovered"];
	const act = (i: int32): void => {
		if (i === 0) focus(a);
		else if (i === 1) minimize(a);
		else if (i === 2) focus(a);
		else if (i === 3) hide(a);
		else if (i === 4) { show(a); focus(a); }
		else if (i === 5) {
			b = createWindow("b", defaultOptions("frame state b", 200 as int32, 150 as int32));
			if (b !== null) { setPosition(b, 700 as int32, 100 as int32); focus(b); }
		}
		else if (i === 6) setFrameWhenInactive(a, true);
		else if (i === 7) { if (b !== null) { setPosition(b, 60 as int32, 40 as int32); setSize(b, 500 as int32, 400 as int32); } }
		else if (i === 8) { if (b !== null) setPosition(b, 700 as int32, 100 as int32); }
	};
	const expectRunning = (i: int32): boolean => i === 0 || i === 2 || i === 4 || i === 6 || i === 8;
	const run = (i: int32): void => {
		if (i >= (phases.length as int32)) {
			console.log(failures === 0 ? "frameStateMacos: all PASS" : `frameStateMacos: ${failures} FAIL`);
			if (b !== null) closeWindow(b);
			closeWindow(a);
			return;
		}
		act(i);
		setTimeout((): void => {
			frames = 0;
			setTimeout((): void => {
				const running = expectRunning(i);
				report(`${phases[i]} (${running ? "ticks" : "no frames"})`, running ? frames > 30 : frames === 0);
				run((i + 1) as int32);
			}, PHASE_MS);
		}, 300);
	};
	setTimeout((): void => { run(0 as int32); }, 300);
	runLoop();
	return failures === 0 ? 0 : 1;
}

exit(main());
