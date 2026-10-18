import { createWindow, defaultOptions, windowRoot, setSize, onWindowEvent, runLoop, WindowEventResized, Window } from "../src/index";
import { exit } from "std/process";

when (macos) {
	@compile("./inputProbeMacos.m", "-fobjc-arc");
	@passL("-framework WebKit");
}
@include("./inputProbeMacos.h");

extern function ipKey(root: Ptr<void>, keyCode: int32, chars: cstring, bare: cstring, mods: int32): void;

const COMMAND: int32 = 8 as int32;

let failures = 0;
let resizedBeforeQuit = 0;
let quitSent = false;
let lateTimerFired = false;

function check(name: string, ok: boolean): void {
	console.log(`${ok ? "PASS" : "FAIL"} ${name}`);
	if (!ok) failures += 1;
}

function main(): int32 {
	const created = createWindow("main", defaultOptions("Ion quit", 400 as int32, 300 as int32));
	if (created === null) {
		console.log("quitMacos: no window");
		return 1;
	}
	const win: Window = created;
	onWindowEvent((label: string, type: int32): void => {
		if (type === WindowEventResized && quitSent) resizedBeforeQuit += 1;
	});
	let sentAt: number = 0;
	setTimeout((): void => {
		setSize(win, 480 as int32, 360 as int32);
		quitSent = true;
		sentAt = Date.now();
		ipKey(windowRoot(win), 0x0C as int32, "q", "q", COMMAND);
	}, 1000);
	setTimeout((): void => { lateTimerFired = true; }, 3000);

	runLoop();
	const took = Date.now() - sentAt;
	check(`runLoop returned ${took} ms after Cmd+Q`, quitSent && took < 500);
	check(`resize queued before Cmd+Q delivered (${resizedBeforeQuit})`, resizedBeforeQuit >= 1);
	check("a timer due after the quit did not fire", !lateTimerFired);
	console.log(failures === 0 ? "quitMacos: all PASS" : `quitMacos: ${failures} FAIL`);
	return failures === 0 ? 0 : 1;
}

exit(main());
