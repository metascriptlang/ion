// Moves the window 500 times inside the modal move loop; every MOVED event must reach the app.
// Run with stdout redirected (GUI subsystem): ringProbe.exe > log.txt; RING_BURST=1 drops the 2 ms spacing.

import {
	createWindow, defaultOptions, commit, onWindowEvent, runLoop, closeWindow, Window,
	WindowEventMoved, WindowEventResized,
} from "../src/index";
import { exit } from "std/process";

@compile("./ringProbe.c");
@include("./ringProbe.h");

extern function ringInit(): int32;
extern function ringRun(): void;
extern function ringDone(): int32;

let moved = 0;
let resized = 0;
let win: Window | null = null;

function finish(): void {
	if (ringDone() === (0 as int32)) {
		setTimeout(finish, 100);
		return;
	}
	setTimeout((): void => {
		console.log("ringProbe: app got moved=" + moved.toString() + " resized=" + resized.toString());
		console.log(moved >= 500 && resized >= 2 ? "ringProbe PASS" : "ringProbe FAIL");
		if (win !== null) closeWindow(win);
	}, 500);
}

function main(): int32 {
	const created = createWindow("main", defaultOptions("Ion ring probe", 480 as int32, 300 as int32));
	if (created === null) return 1;
	const own: Window = created;
	win = own;
	commit(own);
	onWindowEvent((label: string, type: int32): void => {
		if (type === WindowEventMoved) moved++;
		if (type === WindowEventResized) resized++;
	});
	setTimeout((): void => {
		if (ringInit() === (0 as int32)) {
			console.log("ringProbe: window not found");
			closeWindow(own);
			return;
		}
		ringRun();
		setTimeout(finish, 200);
	}, 500);
	runLoop();
	return 0;
}

exit(main());
