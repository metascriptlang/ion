// macOS window-controls check, the counterpart of windowControls.ms. Each control is applied
// through Ion's API and read back through AppKit in windowControlsMacos.m.
// Run: msc build examples/windowControlsMacos.ms && out/debug/windowControlsMacos

import {
	createWindow, defaultOptions, runLoop, onWindowEvent, windowRoot,
	show, hide, focus, minimize, maximize,
	setTitle, setSize, setPosition, setAlwaysOnTop, setDecorations,
	WindowEventCloseRequested, WindowEventDestroyed, WindowEventFocused,
	WindowEventBlurred, WindowEventResized, WindowEventMoved, Window,
} from "../src/index";
import { exit } from "std/process";

when (macos) {
	@compile("./windowControlsMacos.m", "-fobjc-arc");
}
@include("./windowControlsMacos.h");

extern function wcBind(root: Ptr<void>): void;
extern function wcRootW(): int32;
extern function wcRootH(): int32;
extern function wcOuterX(): int32;
extern function wcOuterY(): int32;
extern function wcTitleIs(utf8: cstring): int32;
extern function wcVisible(): int32;
extern function wcMinimized(): int32;
extern function wcMaximized(): int32;
extern function wcDecorated(): int32;
extern function wcTopmost(): int32;
extern function wcActive(): int32;
extern function wcUserClose(): void;

const STEP_MS = 700;
const LAST_STEP = 15;
const TITLE = "Ion é中文 controls";

let failures = 0;
let stepName = "start";
let seenInStep = 0;
let seenEver = 0;

function bit(eventType: int32): int32 {
	return (1 << eventType) as int32;
}

function eventName(eventType: int32): string {
	if (eventType === WindowEventCloseRequested) return "close-requested";
	if (eventType === WindowEventDestroyed) return "destroyed";
	if (eventType === WindowEventFocused) return "focused";
	if (eventType === WindowEventBlurred) return "blurred";
	if (eventType === WindowEventResized) return "resized";
	if (eventType === WindowEventMoved) return "moved";
	return "unknown";
}

function check(what: string, ok: boolean): void {
	if (!ok) failures += 1;
	console.log(`${ok ? "PASS" : "FAIL"} [${stepName}] ${what}`);
}

function expectEvent(eventType: int32, ever: boolean): void {
	const mask = ever ? seenEver : seenInStep;
	check(`event ${eventName(eventType)} received`, (mask & bit(eventType)) !== (0 as int32));
}

function expectClient(w: int32, h: int32): void {
	check(`client ${wcRootW()}x${wcRootH()} == ${w}x${h}`, wcRootW() === w && wcRootH() === h);
}

function act(win: Window, i: int32): void {
	seenInStep = 0;
	if (i === 0) {
		stepName = "create 640x360 decorated";
	} else if (i === 1) {
		stepName = "setTitle";
		setTitle(win, TITLE);
	} else if (i === 2) {
		stepName = "setSize 800x450";
		setSize(win, 800 as int32, 450 as int32);
	} else if (i === 3) {
		stepName = "setPosition 120,90";
		setPosition(win, 120 as int32, 90 as int32);
	} else if (i === 4) {
		stepName = "setAlwaysOnTop true";
		setAlwaysOnTop(win, true);
	} else if (i === 5) {
		stepName = "setAlwaysOnTop false";
		setAlwaysOnTop(win, false);
	} else if (i === 6) {
		stepName = "setDecorations false";
		setDecorations(win, false);
	} else if (i === 7) {
		stepName = "setDecorations true";
		setDecorations(win, true);
	} else if (i === 8) {
		stepName = "hide";
		hide(win);
	} else if (i === 9) {
		stepName = "show";
		show(win);
	} else if (i === 10) {
		stepName = "maximize";
		maximize(win);
	} else if (i === 11) {
		stepName = "setSize 640x360 from maximized";
		setSize(win, 640 as int32, 360 as int32);
	} else if (i === 12) {
		stepName = "minimize";
		minimize(win);
	} else if (i === 13) {
		stepName = "focus from minimized";
		focus(win);
	} else if (i === 14) {
		stepName = "minimize the key window";
		minimize(win);
	} else {
		stepName = "user close";
		wcUserClose();
	}
}

function verify(win: Window, i: int32): void {
	if (i === 0) {
		expectClient(640 as int32, 360 as int32);
		check("decorated", wcDecorated() !== (0 as int32));
		check("visible", wcVisible() !== (0 as int32));
	} else if (i === 1) {
		check(`title is '${TITLE}'`, wcTitleIs(TITLE) !== (0 as int32));
	} else if (i === 2) {
		expectClient(800 as int32, 450 as int32);
		expectEvent(WindowEventResized, false);
	} else if (i === 3) {
		check(`outer ${wcOuterX()},${wcOuterY()} == 120,90`, wcOuterX() === (120 as int32) && wcOuterY() === (90 as int32));
		expectEvent(WindowEventMoved, false);
	} else if (i === 4) {
		check("topmost", wcTopmost() !== (0 as int32));
	} else if (i === 5) {
		check("not topmost", wcTopmost() === (0 as int32));
	} else if (i === 6) {
		check("not decorated", wcDecorated() === (0 as int32));
		expectClient(800 as int32, 450 as int32);
	} else if (i === 7) {
		check("decorated", wcDecorated() !== (0 as int32));
		expectClient(800 as int32, 450 as int32);
	} else if (i === 8) {
		check("not visible", wcVisible() === (0 as int32));
	} else if (i === 9) {
		check("visible", wcVisible() !== (0 as int32));
	} else if (i === 10) {
		check("maximized", wcMaximized() !== (0 as int32));
		check("not minimized", wcMinimized() === (0 as int32));
		expectEvent(WindowEventResized, false);
	} else if (i === 11) {
		check("not maximized", wcMaximized() === (0 as int32));
		expectClient(640 as int32, 360 as int32);
	} else if (i === 12) {
		check("minimized", wcMinimized() !== (0 as int32));
	} else if (i === 13) {
		check("not minimized", wcMinimized() === (0 as int32));
		check("visible", wcVisible() !== (0 as int32));
		check("key window", wcActive() !== (0 as int32));
		expectEvent(WindowEventFocused, false);
	} else if (i === 14) {
		check("minimized", wcMinimized() !== (0 as int32));
		expectEvent(WindowEventBlurred, false);
	}
}

function step(win: Window, i: int32): void {
	act(win, i);
	if (i >= (LAST_STEP as int32)) return;
	setTimeout((): void => {
		console.log(`INFO [${stepName}] active=${wcActive()}`);
		verify(win, i);
		step(win, (i + 1) as int32);
	}, STEP_MS);
}

function main(): int32 {
	const created = createWindow("main", defaultOptions("Ion window controls", 640 as int32, 360 as int32));
	if (created === null) {
		console.log("windowControlsMacos: no window");
		return 1;
	}
	const win: Window = created;
	wcBind(windowRoot(win));
	onWindowEvent((label: string, eventType: int32): void => {
		seenInStep = (seenInStep | bit(eventType)) as int32;
		seenEver = (seenEver | bit(eventType)) as int32;
		console.log(`event ${eventName(eventType)} (${label}) during [${stepName}]`);
	});
	setTimeout((): void => { step(win, 0 as int32); }, STEP_MS);
	runLoop();
	stepName = "after close";
	expectEvent(WindowEventCloseRequested, true);
	expectEvent(WindowEventDestroyed, true);
	console.log(failures === 0 ? "windowControlsMacos: all PASS" : `windowControlsMacos: ${failures} FAIL`);
	return failures === 0 ? 0 : 1;
}

exit(main());
