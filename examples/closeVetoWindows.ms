// A close and a quit the app holds on Windows: WM_SYSCOMMAND SC_CLOSE (the close button's and the system
// menu's path), Alt+F4 through the window proc and a real click on the close button stay held while the
// handlers prevent them, a quit() stays held by preventExit, the app then closes a held window itself,
// and an Alt+F4 nobody prevents closes the last window and ends the loop. Run it in the console session.

import {
	createWindow, defaultOptions, getWindow, closeWindow, windowCount, runLoop, setAlwaysOnTop,
	onWindowEvent, preventClose, onExitRequested, preventExit, quit,
	WindowEventCloseRequested, WindowEventDestroyed,
} from "../src/index";
import { exit } from "std/process";

when (windows) {
	@compile("./windowProbeWindows.c");
}
@include("./windowProbeWindows.h");

extern function wpSysClose(window: int32): void;
extern function wpAltF4(window: int32): void;
extern function wpClickClose(window: int32): int32;

let failures = 0;
let holdClose = true;
let holdExit = true;
let closeRequests = 0;
let exitRequests = 0;
let destroyedSecond = false;
let clicked = 0 as int32;

function check(name: string, ok: boolean): void {
	console.log(`${ok ? "PASS" : "FAIL"} ${name}`);
	if (!ok) failures += 1;
}

function bothOpen(): boolean { return getWindow("main") !== null && windowCount() === (2 as int32); }

function main(): int32 {
	const main = createWindow("main", defaultOptions("Ion close veto", 400 as int32, 300 as int32));
	const second = createWindow("second", defaultOptions("Ion close veto 2", 300 as int32, 200 as int32));
	if (main === null || second === null) {
		console.log("closeVetoWindows: no window");
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

	setTimeout((): void => { wpSysClose(main.id); }, 800);
	setTimeout((): void => {
		check(`a held SC_CLOSE leaves the window open (requests ${closeRequests})`, closeRequests === 1 && bothOpen());
		wpAltF4(main.id);
	}, 1200);
	setTimeout((): void => {
		check(`a held Alt+F4 leaves the window open (requests ${closeRequests})`, closeRequests === 2 && bothOpen());
		setAlwaysOnTop(main, true);
	}, 1600);
	setTimeout((): void => { clicked = wpClickClose(main.id); }, 1900);
	setTimeout((): void => {
		check(`a held click on the close button leaves the window open (injected ${clicked}, requests ${closeRequests})`,
			clicked === (1 as int32) && closeRequests === 3 && bothOpen());
		setAlwaysOnTop(main, false);
		quit();
	}, 2500);
	setTimeout((): void => {
		check(`a held quit() keeps the app running (requests ${exitRequests})`, exitRequests === 1 && bothOpen());
		closeWindow(main);
	}, 2900);
	setTimeout((): void => {
		check("the app closes the held window itself", getWindow("main") === null && windowCount() === (1 as int32));
		holdClose = false;
		holdExit = false;
		wpAltF4(second.id);
	}, 3300);

	runLoop();
	check(`an Alt+F4 nobody prevents closes the last window and ends the loop (requests ${closeRequests})`,
		destroyedSecond && closeRequests === 4);
	console.log(failures === 0 ? "closeVetoWindows: all PASS" : `closeVetoWindows: ${failures} FAIL`);
	return failures === 0 ? 0 : 1;
}

exit(main());
