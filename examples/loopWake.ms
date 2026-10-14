// Ion's loop is msc's loop: a raw native thread wakes an idle window, a timer
// fires, a spawn result resumes an await, and text round-trips the clipboard.
// Run it with stdout redirected (GUI subsystem): loopWake.exe > log.txt
// Idle CPU is measured from outside: sample the process before and after the wake.

import {
	createWindow, defaultOptions, commit, requestFrame,
	onWake, onFrame, readClipboardText, writeClipboardText, runLoop, Window,
} from "../src/index";
import { exit } from "std/process";

@compile("./loopWake.c");
@include("./loopWake.h");

extern function wakeAfter(ms: int32): void;
extern function elapsedMs(): int32;

const WAKE_AFTER_MS: int32 = 5000 as int32;

function compute(): int32 {
	let sum = 0;
	for (let i = 0; i < 1000000; i++) { sum = sum + i % 7; }
	return sum;
}

async function awaitSpawn(): Promise<void> {
	const sum = await spawn(() => compute());
	console.log(`[${elapsedMs()} ms] await of a spawn resumed in runLoop: ${sum}`);
}

function main(): int32 {
	elapsedMs();
	const created = createWindow("main", defaultOptions("Ion loop wake", 640 as int32, 360 as int32));
	if (created === null) {
		console.log("loopWake: no window");
		return 1;
	}
	const win: Window = created;
	commit(win);

	onWake((): void => {
		console.log(`[${elapsedMs()} ms] onWake ran on the loop thread; requesting one frame`);
		requestFrame(win);
	});
	onFrame((window: int32, timeMs: float64): void => {
		console.log(`[${elapsedMs()} ms] frame`);
	});

	setTimeout((): void => {
		console.log(`[${elapsedMs()} ms] 500 ms setTimeout fired in runLoop`);
	}, 500);
	awaitSpawn();

	const wrote = writeClipboardText("ion clipboard é中文 round trip");
	console.log(`clipboard write: ${wrote}, read back: '${readClipboardText()}'`);

	wakeAfter(WAKE_AFTER_MS);
	console.log(`[${elapsedMs()} ms] running; native thread wakes the loop in ${WAKE_AFTER_MS} ms`);
	runLoop();
	return 0;
}

exit(main());
