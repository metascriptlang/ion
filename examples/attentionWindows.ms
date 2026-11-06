// Beep and taskbar attention on Windows: requestUserAttention flashes the taskbar button of a window that
// is not active (the shell hook's HSHELL_FLASH names it), Critical flashes again after None stopped it,
// and a request for the active window flashes nothing (tao). Run it in the console session.

import {
	createWindow, defaultOptions, closeWindow, runLoop, focus, minimize, beep,
	requestUserAttention, AttentionNone, AttentionInformational, AttentionCritical,
} from "../src/index";
import { exit } from "std/process";

when (windows) {
	@compile("./windowProbeWindows.c");
}
@include("./windowProbeWindows.h");

extern function wpWindowState(window: int32): int32;
extern function wpWatchFlashes(): int32;
extern function wpFlashes(window: int32): int32;

let failures = 0;

function check(name: string, ok: boolean): void {
	console.log(`${ok ? "PASS" : "FAIL"} ${name}`);
	if (!ok) failures += 1;
}

function main(): int32 {
	const main = createWindow("main", defaultOptions("Ion attention", 320 as int32, 200 as int32));
	const second = createWindow("second", defaultOptions("Ion attention 2", 320 as int32, 200 as int32));
	if (main === null || second === null) {
		console.log("attentionWindows: no window");
		return 1;
	}
	check("a shell hook window is registered", wpWatchFlashes() === (1 as int32));
	let stopped = 0 as int32;
	let mainBefore = 0 as int32;
	setTimeout((): void => {
		beep();
		console.log("PASS beep returned");
		focus(main);
		minimize(second);
	}, 800);
	setTimeout((): void => {
		console.log(`INFO main state ${wpWindowState(main.id)}, second state ${wpWindowState(second.id)} (1 active, 2 minimized)`);
		requestUserAttention(second, AttentionInformational);
	}, 1200);
	setTimeout((): void => {
		check(`Informational flashed the minimized window's taskbar button (${wpFlashes(second.id)} HSHELL_FLASH)`,
			wpFlashes(second.id) >= (1 as int32));
		requestUserAttention(second, AttentionNone);
	}, 1800);
	setTimeout((): void => {
		stopped = wpFlashes(second.id);
		requestUserAttention(second, AttentionCritical);
	}, 2100);
	setTimeout((): void => {
		check(`Critical flashed it again after None (${stopped} -> ${wpFlashes(second.id)})`, wpFlashes(second.id) > stopped);
		requestUserAttention(second, AttentionNone);
		mainBefore = wpFlashes(main.id);
		if (wpWindowState(main.id) === (1 as int32)) requestUserAttention(main, AttentionCritical);
	}, 2700);
	setTimeout((): void => {
		if (wpWindowState(main.id) === (1 as int32)) {
			check(`a request for the active window flashes nothing (${mainBefore} -> ${wpFlashes(main.id)})`,
				wpFlashes(main.id) === mainBefore);
		} else {
			console.log("INFO main is not the active window, so the no-op for an active window is not checked");
		}
		closeWindow(second);
		closeWindow(main);
	}, 3000);
	runLoop();
	console.log(failures === 0 ? "attentionWindows: all PASS" : `attentionWindows: ${failures} FAIL`);
	return failures === 0 ? 0 : 1;
}

exit(main());
