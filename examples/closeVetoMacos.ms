// A close and a quit the app holds: a title-bar close (performClose:, the button's path) and
// Cmd+Q stay held while the handlers prevent them, the app then closes a held window itself,
// and a close nobody prevents still closes the window and ends the loop with the last one.

import {
	createWindow, defaultOptions, windowRoot, getWindow, closeWindow, windowCount, runLoop,
	onWindowEvent, preventClose, onExitRequested, preventExit,
	WindowEventCloseRequested, WindowEventDestroyed,
} from "../src/index";
import { exit } from "std/process";

when (macos) {
	@compile("./inputProbeMacos.m", "-fobjc-arc");
	@compile("./multiWindowMacos.m", "-fobjc-arc");
	@passL("-framework WebKit");
}
@include("./inputProbeMacos.h");
@include("./multiWindowMacos.h");

extern function ipKey(root: Ptr<void>, keyCode: int32, chars: cstring, bare: cstring, mods: int32): void;
extern function probeUserClose(root: Ptr<void>): void;

const COMMAND: int32 = 8 as int32;

let failures = 0;
let holdClose = true;
let holdExit = true;
let closeRequests = 0;
let exitRequests = 0;
let destroyedSecond = false;

function check(name: string, ok: boolean): void {
	console.log(`${ok ? "PASS" : "FAIL"} ${name}`);
	if (!ok) failures += 1;
}

function main(): int32 {
	const main = createWindow("main", defaultOptions("Ion close veto", 400 as int32, 300 as int32));
	const second = createWindow("second", defaultOptions("Ion close veto 2", 300 as int32, 200 as int32));
	if (main === null || second === null) {
		console.log("closeVetoMacos: no window");
		return 1;
	}
	onWindowEvent((label: string, type: int32): void => {
		if (type === WindowEventCloseRequested) {
			closeRequests += 1;
			if (holdClose) preventClose();
		}
		if (type === WindowEventDestroyed && label === "second") destroyedSecond = true;
	});
	onExitRequested((): void => {
		exitRequests += 1;
		if (holdExit) preventExit();
	});

	setTimeout((): void => { probeUserClose(windowRoot(main)); }, 800);
	setTimeout((): void => {
		check(`a held title-bar close leaves the window open (requests ${closeRequests})`,
			closeRequests === 1 && getWindow("main") !== null && windowCount() === (2 as int32));
		ipKey(windowRoot(main), 0x0C as int32, "q", "q", COMMAND);
	}, 1300);
	setTimeout((): void => {
		check(`a held Cmd+Q keeps the app running (requests ${exitRequests})`,
			exitRequests === 1 && windowCount() === (2 as int32));
		closeWindow(main);
	}, 1900);
	setTimeout((): void => {
		check("the app closes the held window itself", getWindow("main") === null && windowCount() === (1 as int32));
		holdClose = false;
		holdExit = false;
		probeUserClose(windowRoot(second));
	}, 2300);

	runLoop();
	check(`a close nobody prevents closes the last window and ends the loop (requests ${closeRequests})`,
		destroyedSecond && closeRequests === 2);
	console.log(failures === 0 ? "closeVetoMacos: all PASS" : `closeVetoMacos: ${failures} FAIL`);
	return failures === 0 ? 0 : 1;
}

exit(main());
