// quit() from a timer: the exit-requested handlers run, the first request is held with preventExit
// and the window stays, the second ends runLoop.

import { createWindow, defaultOptions, windowCount, runLoop, onExitRequested, preventExit, quit } from "../src/index";
import { exit } from "std/process";

let failures = 0;
let exitRequests = 0;
let hold = true;
let windowsWhileHeld = 0;

function check(name: string, ok: boolean): void {
	console.log(`quitFromCode: ${ok ? "PASS" : "FAIL"} ${name}`);
	if (!ok) failures += 1;
}

function main(): int32 {
	if (createWindow("main", defaultOptions("Ion quit", 320 as int32, 200 as int32)) === null) {
		console.log("quitFromCode: no window");
		return 1;
	}
	onExitRequested((): void => {
		exitRequests += 1;
		if (hold) preventExit();
	});
	setTimeout((): void => { quit(); }, 300);
	setTimeout((): void => {
		windowsWhileHeld = windowCount();
		hold = false;
		quit();
	}, 800);
	setTimeout((): void => { check("the loop ended within 3 s", false); exit(1); }, 3000);
	runLoop();
	check("both requests reached the handlers", exitRequests == 2);
	check("the held request kept the window", windowsWhileHeld == 1);
	return failures == 0 ? 0 : 1;
}

exit(main());
