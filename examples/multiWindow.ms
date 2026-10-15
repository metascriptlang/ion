// WebView2Loader.dll must sit next to the exe (vendor/webview2/runtime/x64/).

import {
	createWindow, getWindow, defaultOptions, windowRoot, windowDevice, commit, setPosition, windowCount, requestFrame,
	createWebview, getWebview, webviewById, webviewWindowId, webviewNode, setWebviewBounds, forwardPointer,
	emit, listen, messageWebviewId, runLoop, onPointer, onKey, onFrame, onWindowEvent, keyName,
	PointerEvent, PointerKind, KeyEvent, KeyAction, Webview, Window,
	PointerMove, PointerDown, PointerUp, PointerWheel, PointerHWheel, PointerLeave,
	WindowEventCloseRequested, WindowEventDestroyed,
} from "../src/index";
import { contentAttach, contentMove, contentPanel } from "./content/content";
import { exit } from "std/process";

@compile("./multiWindow.c");
@include("./multiWindow.h");

extern function mwClick(window: int32, x: int32, y: int32): void;
extern function mwKey(window: int32, vk: int32, scancode: int32): void;
extern function mwClose(window: int32): void;
extern function mwPixel(window: int32, x: int32, y: int32): int32;

const PAGE = "data:text/html,<body style='margin:0;font:16px sans-serif;background:%23f4f4f4'>"
	+ "<div id=out style='padding:24px'>webview</div><script>"
	+ "window.__ion__.setReceiver((n,p)=>{if(n==='who'){document.getElementById('out').textContent='window '+p;window.__ion__.post('ack',p)}});"
	+ "addEventListener('pointerdown',e=>window.__ion__.post('webview.click',e.clientX+','+e.clientY));"
	+ "window.__ion__.post('ready','')</script></body>";

const STEP_MS = 400;
const BLUE: int32 = 0x2f6fdb as int32;
const GREEN: int32 = 0x2fa84f as int32;
const RED: int32 = 0xd2452f as int32;

struct Rect {
	x: int32;
	y: int32;
	w: int32;
	h: int32;
}

const panelRect: Rect = { x: 24 as int32, y: 24 as int32, w: 300 as int32, h: 160 as int32 };
const webRect: Rect = { x: 340 as int32, y: 24 as int32, w: 320 as int32, h: 420 as int32 };

function inside(r: Rect, x: float64, y: float64): boolean {
	return x >= (r.x as float64) && y >= (r.y as float64)
		&& x < ((r.x + r.w) as float64) && y < ((r.y + r.h) as float64);
}

function pointerKind(e: PointerEvent): int32 {
	return match (e.kind) {
		PointerKind.Button => e.pressed ? PointerDown : PointerUp,
		PointerKind.Motion => PointerMove,
		PointerKind.Wheel => e.dx !== 0.0 ? PointerHWheel : PointerWheel,
		PointerKind.Leave => PointerLeave,
	};
}

function near(got: int32, want: int32): boolean {
	if (got < (0 as int32)) return false;
	const dr = Math.abs(((got >> 16) & 0xff) - ((want >> 16) & 0xff));
	const dg = Math.abs(((got >> 8) & 0xff) - ((want >> 8) & 0xff));
	const db = Math.abs((got & 0xff) - (want & 0xff));
	return dr <= 8 && dg <= 8 && db <= 8;
}

function hex(v: int32): string {
	return v < (0 as int32) ? "none" : `rgb(${(v >> 16) & 0xff},${(v >> 8) & 0xff},${v & 0xff})`;
}

let failures: int32 = 0 as int32;

function check(what: string, ok: boolean): void {
	if (!ok) failures = (failures + 1) as int32;
	console.log(`${ok ? "PASS" : "FAIL"} ${what}`);
}

function openPane(label: string, x: int32, rgb: int32): Webview | null {
	const created = createWindow(label, defaultOptions(`Ion window ${label}`, 690 as int32, 470 as int32));
	if (created === null) return null as unknown as Webview | null;
	const win: Window = created;
	setPosition(win, x, 60 as int32);
	const opened = createWebview(win, `web-${label}`, PAGE);
	if (opened === null) return null as unknown as Webview | null;
	const web: Webview = opened;
	const root = windowRoot(win);
	const panel = contentPanel(windowDevice(win), panelRect.w, panelRect.h, `native panel ${label}`, rgb as uint32);
	contentAttach(root, panel, 1 as int32);
	contentAttach(root, webviewNode(web), 1 as int32);
	contentMove(panel, panelRect.x, panelRect.y, panelRect.w, panelRect.h);
	contentMove(webviewNode(web), webRect.x, webRect.y, webRect.w, webRect.h);
	setWebviewBounds(web, webRect.x, webRect.y, webRect.w, webRect.h);
	commit(win);
	return opened;
}

function main(): int32 {
	const openedOne = openPane("one", 40 as int32, BLUE);
	const openedTwo = openPane("two", 760 as int32, GREEN);
	if (openedOne === null || openedTwo === null) {
		console.log("multiWindow: window or webview creation failed");
		return 1;
	}
	const webOne: Webview = openedOne;
	const webTwo: Webview = openedTwo;
	const one = webviewWindowId(webOne);
	const two = webviewWindowId(webTwo);
	console.log(`multiWindow: window one id ${one}, window two id ${two}, windowCount ${windowCount()}`);

	const labelOf = (window: int32): string => window === one ? "one" : window === two ? "two" : `?${window}`;
	const paneWeb = (window: int32): Webview => window === one ? webOne : webTwo;

	let acks = "";
	let pointerLog = "";
	let keyLog = "";
	let webClicks = "";
	let events = "";
	let framesTwo: int32 = 0 as int32;

	onPointer((e: PointerEvent): void => {
		if (inside(webRect, e.x, e.y)) {
			const delta = e.dx !== 0.0 ? e.dx : e.dy;
			forwardPointer(paneWeb(e.window), pointerKind(e), e.x - (webRect.x as float64), e.y - (webRect.y as float64), e.button, delta);
			return;
		}
		if (e.kind === PointerKind.Button && e.pressed) {
			console.log(`host click: window ${labelOf(e.window)} (id ${e.window}) at ${e.x as int32},${e.y as int32}`);
			pointerLog = pointerLog + `${labelOf(e.window)}@${e.x as int32},${e.y as int32} `;
		}
	});
	onKey((e: KeyEvent): void => {
		if (e.action !== KeyAction.Press) return;
		console.log(`host key: window ${labelOf(e.window)} (id ${e.window}) ${keyName(e.key)} text '${e.text}'`);
		keyLog = keyLog + `${labelOf(e.window)}:${keyName(e.key)} `;
	});
	onFrame((window: int32, timeMs: float64): void => {
		if (window === two) framesTwo = (framesTwo + 1) as int32;
	});
	onWindowEvent((label: string, type: int32): void => {
		if (type === WindowEventCloseRequested) events = events + `${label}:close-requested `;
		if (type === WindowEventDestroyed) events = events + `${label}:destroyed `;
	});
	listen((name: string, payload: string): void => {
		const sender = webviewById(messageWebviewId());
		if (sender === null) return;
		const web: Webview = sender;
		const from = labelOf(webviewWindowId(web));
		if (name === "ready") {
			console.log(`ipc ready from webview of window ${from}`);
			emit(web, "who", from);
		} else if (name === "ack") {
			console.log(`ipc ack from webview of window ${from}: '${payload}'`);
			acks = acks + `${from}=${payload} `;
		} else if (name === "webview.click") {
			console.log(`webview.click from window ${from}: ${payload}`);
			webClicks = webClicks + `${from}:${payload} `;
		}
	});

	const afterCloseTwo = (): void => {
		check(`window two pointer after window one closed: ${pointerLog}`, pointerLog === "two@130,120 ");
		check(`window two frame after window one closed: ${framesTwo} frame(s)`, framesTwo > (0 as int32));
		check(`window two IPC after window one closed: ${acks}`, acks === "two=two ");
		const px = mwPixel(two, 50 as int32, 50 as int32);
		check(`window two panel still drawn: ${hex(px)}`, near(px, GREEN));
		const late = mwPixel(two, 60 as int32, 230 as int32);
		check(`window two draws a panel added after window one closed: ${hex(late)}`, near(late, RED));
		console.log("multiWindow: closing window two (the last window)");
		mwClose(two);
	};

	const afterCloseOne = (): void => {
		check(`events after closing window one: ${events}`, events === "one:close-requested one:destroyed ");
		check(`windowCount after closing window one: ${windowCount()}`, windowCount() === (1 as int32));
		check("window one's webview released", getWebview("web-one") === null);
		pointerLog = "";
		acks = "";
		framesTwo = 0 as int32;
		mwClick(two, 130 as int32, 120 as int32);
		const found = getWindow("two");
		if (found !== null) {
			const winTwo: Window = found;
			const late = contentPanel(windowDevice(winTwo), panelRect.w, 100 as int32, "added after close", RED as uint32);
			contentAttach(windowRoot(winTwo), late, 1 as int32);
			contentMove(late, panelRect.x, 200 as int32, panelRect.w, 100 as int32);
			commit(winTwo);
			requestFrame(winTwo);
		}
		emit(webTwo, "who", "two");
		setTimeout(afterCloseTwo, STEP_MS * 2);
	};

	const afterWebClicks = (): void => {
		check(`webview clicks reach each window's own webview: ${webClicks}`, webClicks === "one:160,176 two:80,276 ");
		const pxOne = mwPixel(one, 50 as int32, 50 as int32);
		const pxTwo = mwPixel(two, 50 as int32, 50 as int32);
		check(`window one panel drawn: ${hex(pxOne)}`, near(pxOne, BLUE));
		check(`window two panel drawn: ${hex(pxTwo)}`, near(pxTwo, GREEN));
		console.log("multiWindow: closing window one through WM_CLOSE");
		mwClose(one);
		setTimeout(afterCloseOne, STEP_MS);
	};

	const afterKeys = (): void => {
		check(`key records carry their window: ${keyLog}`, keyLog === "one:KeyA two:KeyB ");
		mwClick(one, 500 as int32, 200 as int32);
		mwClick(two, 420 as int32, 300 as int32);
		setTimeout(afterWebClicks, STEP_MS * 2);
	};

	const afterClicks = (): void => {
		check(`pointer records carry their window: ${pointerLog}`, pointerLog === "one@100,100 two@120,110 ");
		mwKey(one, 0x41 as int32, 0x1e as int32);
		mwKey(two, 0x42 as int32, 0x30 as int32);
		setTimeout(afterKeys, STEP_MS);
	};

	let waited: int32 = 0 as int32;
	const waitReady = (): void => {
		const ready = acks === "one=one two=two " || acks === "two=two one=one ";
		if (!ready && waited < (75 as int32)) {
			waited = (waited + 1) as int32;
			setTimeout(waitReady, 200);
			return;
		}
		check(`each webview's reply came back from that webview: ${acks}`, ready);
		mwClick(one, 100 as int32, 100 as int32);
		mwClick(two, 120 as int32, 110 as int32);
		setTimeout(afterClicks, STEP_MS);
	};
	setTimeout(waitReady, 200);

	runLoop();
	check(`loop ended after the last window closed, events: ${events}`,
		events === "one:close-requested one:destroyed two:close-requested two:destroyed " && windowCount() === (0 as int32));
	console.log(failures === (0 as int32) ? "multiWindow: all PASS" : `multiWindow: ${failures} FAIL`);
	return failures === (0 as int32) ? 0 : 1;
}

exit(main());
