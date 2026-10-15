import {
	createWindow, defaultOptions, runLoop, onWindowEvent,
	show, hide, focus, minimize, maximize,
	setTitle, setSize, setPosition, setAlwaysOnTop, setDecorations,
	WindowEventCloseRequested, WindowEventDestroyed, WindowEventFocused,
	WindowEventBlurred, WindowEventResized, WindowEventMoved, Window,
} from "../src/index";
import { exit } from "std/process";

@compile("./windowControls.c");
@include("./windowControls.h");

extern function wcClientX(): int32;
extern function wcClientY(): int32;
extern function wcClientW(): int32;
extern function wcClientH(): int32;
extern function wcOuterX(): int32;
extern function wcOuterY(): int32;
extern function wcDpi(): int32;
extern function wcScale(dip: int32): int32;
extern function wcHasCaption(): int32;
extern function wcHasThickFrame(): int32;
extern function wcTopmost(): int32;
extern function wcVisible(): int32;
extern function wcIconic(): int32;
extern function wcZoomed(): int32;
extern function wcForeground(): int32;
extern function wcUserClose(): void;
extern function wcTitleIs(utf8: cstring): int32;

const STEP_MS = 200;
const TITLE = "Ion é中文 controls";

let failures: int32 = 0 as int32;
let stepName = "start";
let seenInStep: int32 = 0 as int32;
let seenEver: int32 = 0 as int32;
let focused = false;
let focusedBeforeMinimize = false;
let originX: int32 = 0 as int32;
let originY: int32 = 0 as int32;

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
	if (!ok) failures = (failures + 1) as int32;
	console.log(`${ok ? "PASS" : "FAIL"} [${stepName}] ${what}`);
}

function expectEvent(eventType: int32, ever: boolean): void {
	const mask = ever ? seenEver : seenInStep;
	check(`event ${eventName(eventType)} received`, (mask & bit(eventType)) !== (0 as int32));
}

function expectClient(w: int32, h: int32): void {
	const ew = wcScale(w);
	const eh = wcScale(h);
	check(`client ${wcClientW()}x${wcClientH()} == ${ew}x${eh} (${w}x${h} dip at ${wcDpi()} dpi)`,
	      wcClientW() === ew && wcClientH() === eh);
}

function rememberOrigin(): void {
	originX = wcClientX();
	originY = wcClientY();
}

function expectOriginKept(): void {
	check(`client origin ${wcClientX()},${wcClientY()} == ${originX},${originY}`,
	      wcClientX() === originX && wcClientY() === originY);
}

function act(win: Window, i: int32): void {
	if (i === 0) {
		stepName = "create 640x360 decorated";
	} else if (i === 1) {
		stepName = "focus";
		focus(win);
	} else if (i === 2) {
		stepName = "setTitle";
		setTitle(win, TITLE);
	} else if (i === 3) {
		stepName = "setSize 800x450";
		setSize(win, 800 as int32, 450 as int32);
	} else if (i === 4) {
		stepName = "setPosition 120,90";
		setPosition(win, 120 as int32, 90 as int32);
	} else if (i === 5) {
		stepName = "setAlwaysOnTop true";
		setAlwaysOnTop(win, true);
	} else if (i === 6) {
		stepName = "setAlwaysOnTop false";
		setAlwaysOnTop(win, false);
	} else if (i === 7) {
		stepName = "setDecorations false";
		rememberOrigin();
		setDecorations(win, false);
	} else if (i === 8) {
		stepName = "setSize 500x300 undecorated";
		setSize(win, 500 as int32, 300 as int32);
	} else if (i === 9) {
		stepName = "setDecorations true";
		rememberOrigin();
		setDecorations(win, true);
	} else if (i === 10) {
		stepName = "hide";
		hide(win);
	} else if (i === 11) {
		stepName = "show";
		show(win);
	} else if (i === 12) {
		stepName = "minimize";
		focusedBeforeMinimize = focused;
		minimize(win);
	} else if (i === 13) {
		stepName = "maximize";
		maximize(win);
	} else if (i === 14) {
		stepName = "setSize 640x360 from maximized";
		setSize(win, 640 as int32, 360 as int32);
	} else {
		stepName = "user close";
		wcUserClose();
	}
	seenInStep = 0 as int32;
}

function verify(i: int32): void {
	if (i === 0) {
		expectClient(640 as int32, 360 as int32);
		check("has WS_CAPTION", wcHasCaption() !== (0 as int32));
		check("has WS_THICKFRAME", wcHasThickFrame() !== (0 as int32));
		check("visible", wcVisible() !== (0 as int32));
	} else if (i === 1) {
		check("foreground window", wcForeground() !== (0 as int32));
		expectEvent(WindowEventFocused, true);
	} else if (i === 2) {
		check(`title is '${TITLE}'`, wcTitleIs(TITLE) !== (0 as int32));
	} else if (i === 3) {
		expectClient(800 as int32, 450 as int32);
		expectEvent(WindowEventResized, false);
	} else if (i === 4) {
		check(`outer position ${wcOuterX()},${wcOuterY()} == 120,90`,
		      wcOuterX() === (120 as int32) && wcOuterY() === (90 as int32));
		expectEvent(WindowEventMoved, false);
	} else if (i === 5) {
		check("WS_EX_TOPMOST set", wcTopmost() !== (0 as int32));
	} else if (i === 6) {
		check("WS_EX_TOPMOST clear", wcTopmost() === (0 as int32));
	} else if (i === 7) {
		check("WS_CAPTION clear", wcHasCaption() === (0 as int32));
		expectClient(800 as int32, 450 as int32);
		expectOriginKept();
	} else if (i === 8) {
		expectClient(500 as int32, 300 as int32);
	} else if (i === 9) {
		check("has WS_CAPTION", wcHasCaption() !== (0 as int32));
		expectClient(500 as int32, 300 as int32);
		expectOriginKept();
	} else if (i === 10) {
		check("not visible", wcVisible() === (0 as int32));
	} else if (i === 11) {
		check("visible", wcVisible() !== (0 as int32));
	} else if (i === 12) {
		check("iconic", wcIconic() !== (0 as int32));
		if (focusedBeforeMinimize) expectEvent(WindowEventBlurred, false);
		else console.log("SKIP [minimize] event blurred: the window was not focused (another app took the foreground)");
	} else if (i === 13) {
		check("zoomed and not iconic", wcZoomed() !== (0 as int32) && wcIconic() === (0 as int32));
		expectEvent(WindowEventResized, false);
	} else if (i === 14) {
		check("not zoomed", wcZoomed() === (0 as int32));
		expectClient(640 as int32, 360 as int32);
	}
}

function step(win: Window, i: int32): void {
	act(win, i);
	if (i > (14 as int32)) return;
	setTimeout((): void => {
		console.log(`INFO [${stepName}] foreground=${wcForeground()} focused-by-events=${focused}`);
		verify(i);
		step(win, (i + 1) as int32);
	}, STEP_MS);
}

function main(): int32 {
	const created = createWindow("main", defaultOptions("Ion window controls", 640 as int32, 360 as int32));
	if (created === null) {
		console.log("windowControls: no window");
		return 1;
	}
	const win: Window = created;
	onWindowEvent((label: string, eventType: int32): void => {
		seenInStep = (seenInStep | bit(eventType)) as int32;
		seenEver = (seenEver | bit(eventType)) as int32;
		if (eventType === WindowEventFocused) focused = true;
		if (eventType === WindowEventBlurred) focused = false;
		console.log(`event ${eventName(eventType)} (${label}) during [${stepName}]`);
	});
	step(win, 0 as int32);
	runLoop();
	stepName = "after close";
	expectEvent(WindowEventCloseRequested, true);
	expectEvent(WindowEventDestroyed, true);
	console.log(failures === (0 as int32) ? "windowControls: all PASS" : `windowControls: ${failures} FAIL`);
	return failures === (0 as int32) ? 0 : 1;
}

exit(main());
