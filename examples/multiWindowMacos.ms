// macOS multi-window close check. performClose: takes the same close-request path as the
// title-bar button. Closing one of two windows must leave the loop and the other window running;
// the loop ends only after the last window's destroyed event was delivered.
// Run: msc build examples/multiWindowMacos.ms && out/debug/multiWindowMacos

import {
	createWindow, defaultOptions, windowRoot, setSize, windowCount, onWindowEvent, runLoop,
	WindowEventCloseRequested, WindowEventDestroyed, WindowEventResized, Window,
} from "../src/index";
import { exit } from "std/process";

when (macos) {
	@compile("./multiWindowMacos.m", "-fobjc-arc");
}
@include("./multiWindowMacos.h");

extern function probeUserClose(root: Ptr<void>): void;

let aClose = 0;
let aDestroyed = 0;
let bClose = 0;
let bDestroyed = 0;
let bResizedAfterAClosed = 0;
let aGone = false;
let countAfterA = -1;
let timerAfterAClosed = false;
let failures = 0;

function check(name: string, ok: boolean): void {
	console.log(`${ok ? "ok  " : "FAIL"} ${name}`);
	if (!ok) failures += 1;
}

function main(): int32 {
	const a = createWindow("a", defaultOptions("probe a", 400 as int32, 300 as int32));
	const b = createWindow("b", defaultOptions("probe b", 400 as int32, 300 as int32));
	if (a === null || b === null) {
		console.log("FAIL could not create two windows");
		return 1;
	}
	const winA: Window = a;
	const winB: Window = b;

	onWindowEvent((label: string, type: int32): void => {
		console.log(`event ${label} ${type}`);
		if (label === "a" && type === WindowEventCloseRequested) aClose += 1;
		if (label === "a" && type === WindowEventDestroyed) { aDestroyed += 1; aGone = true; }
		if (label === "b" && type === WindowEventCloseRequested) bClose += 1;
		if (label === "b" && type === WindowEventDestroyed) bDestroyed += 1;
		if (label === "b" && type === WindowEventResized && aGone) bResizedAfterAClosed += 1;
	});

	setTimeout((): void => { probeUserClose(windowRoot(winA)); }, 1500);
	setTimeout((): void => {
		countAfterA = windowCount() as int32;
		timerAfterAClosed = true;
		setSize(winB, 520 as int32, 420 as int32);
	}, 2500);
	setTimeout((): void => { probeUserClose(windowRoot(winB)); }, 3500);

	runLoop();

	check("a: close-requested then destroyed", aClose === 1 && aDestroyed === 1);
	check("loop kept running after a closed (timer fired)", timerAfterAClosed);
	check("one window left after a closed", countAfterA === 1);
	check("b still gets events after a closed", bResizedAfterAClosed >= 1);
	check("b: close-requested then destroyed delivered before runLoop returned", bClose === 1 && bDestroyed === 1);
	check("no windows left", (windowCount() as int32) === 0);
	console.log(failures === 0 ? "PASS" : "FAIL");
	return failures as int32;
}

exit(main());
