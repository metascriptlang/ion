// macOS content input check: the nativeContent layout (a panel, a webview child, a badge over
// the webview's corner) driven by NSEvents posted to the app's own queue (inputProbeMacos.m).
// Checks the window records (resize, focus, pointer button, key, text, preedit), the app's
// hit-test giving the badge the click over the webview, the webview's own click in CSS pixels,
// and keyboard focus moving between the content and the webview.
// Run: msc build examples/contentInputMacos.ms && out/debug/contentInputMacos

import {
	createWindow, defaultOptions, windowRoot, windowDevice, commit, focusContent,
	createWebview, webviewNode, setWebviewBounds, focusWebview, listen, runLoop, closeWindow,
	onPointer, onKey, onText, onImePreedit, onFocus, onResize, keyName, keyMods,
	PointerEvent, PointerKind, KeyEvent, KeyAction, KeyMod, Webview, Window,
} from "../src/index";
import { contentAttach, contentMove, contentPanel } from "./content/content";
import { exit } from "std/process";

when (macos) {
	@compile("./inputProbeMacos.m", "-fobjc-arc");
	@passL("-framework WebKit");
}
@include("./inputProbeMacos.h");

extern function ipActivate(root: Ptr<void>): void;
extern function ipClick(root: Ptr<void>, x: int32, y: int32, button: int32, mods: int32): void;
extern function ipKey(root: Ptr<void>, keyCode: int32, chars: cstring, bare: cstring, mods: int32): void;
extern function ipMarked(root: Ptr<void>, utf8: cstring, caretUtf16: int32): void;
extern function ipCommit(root: Ptr<void>, utf8: cstring): void;
extern function ipWebviewIsFirstResponder(root: Ptr<void>): int32;

const PAGE = "data:text/html,<body style='margin:0;background:%23f4f4f4'><input id=box>"
	+ "<script>addEventListener('pointerdown',e=>window.__ion__.post('webview.click',e.clientX+','+e.clientY));"
	+ "addEventListener('keydown',e=>window.__ion__.post('webview.key',e.code))</script></body>";

const STEP_MS = 300;
const SHIFT: int32 = 1 as int32;
const CTRL: int32 = 2 as int32;

struct Rect {
	x: int32;
	y: int32;
	w: int32;
	h: int32;
}

function inside(r: Rect, x: float64, y: float64): boolean {
	return x >= (r.x as float64) && y >= (r.y as float64)
		&& x < ((r.x + r.w) as float64) && y < ((r.y + r.h) as float64);
}

const panelRect: Rect = { x: 24 as int32, y: 24 as int32, w: 420 as int32, h: 220 as int32 };
const webRect: Rect = { x: 480 as int32, y: 24 as int32, w: 560 as int32, h: 520 as int32 };
const badgeRect: Rect = { x: 900 as int32, y: 12 as int32, w: 160 as int32, h: 64 as int32 };

let failures = 0;
let stepName = "start";
let scale = 0.0;
let resizes = 0;
let lastW: int32 = 0 as int32;
let lastH: int32 = 0 as int32;
let focusTrue = 0;
let clicks = "";
let keys = "";
let texts = "";
let preedits = "";
let pageClicks = "";
let pageKeys = "";

function check(what: string, ok: boolean): void {
	if (!ok) failures += 1;
	console.log(`${ok ? "PASS" : "FAIL"} [${stepName}] ${what}`);
}

function hitName(x: float64, y: float64): string {
	if (inside(badgeRect, x, y)) return "badge";
	if (inside(webRect, x, y)) return "webview";
	if (inside(panelRect, x, y)) return "panel";
	return "background";
}

function resetStep(name: string): void {
	stepName = name;
	clicks = "";
	keys = "";
	texts = "";
	preedits = "";
	pageClicks = "";
	pageKeys = "";
}

function act(root: Ptr<void>, i: int32): void {
	if (i === 0) {
		resetStep("activate");
		ipActivate(root);
	} else if (i === 1) {
		resetStep("click panel");
		ipClick(root, 200 as int32, 120 as int32, 1 as int32, 0 as int32);
	} else if (i === 2) {
		resetStep("click badge over the webview");
		ipClick(root, 980 as int32, 44 as int32, 1 as int32, 0 as int32);
	} else if (i === 3) {
		resetStep("click webview");
		ipClick(root, 700 as int32, 260 as int32, 1 as int32, 0 as int32);
	} else if (i === 4) {
		resetStep("key B into the webview");
		ipKey(root, 0x0B as int32, "b", "b", 0 as int32);
	} else if (i === 5) {
		resetStep("Shift+click panel");
		ipClick(root, 200 as int32, 120 as int32, 1 as int32, SHIFT);
	} else if (i === 6) {
		resetStep("key A");
		ipKey(root, 0x00 as int32, "a", "a", 0 as int32);
	} else if (i === 7) {
		resetStep("Shift+A");
		ipKey(root, 0x00 as int32, "A", "a", SHIFT);
	} else if (i === 8) {
		resetStep("Enter");
		ipKey(root, 0x24 as int32, "\r", "\r", 0 as int32);
	} else if (i === 9) {
		resetStep("Ctrl+C");
		ipKey(root, 0x08 as int32, "\u0003", "c", CTRL);
	} else if (i === 10) {
		resetStep("e acute from the layout");
		ipKey(root, 0x0E as int32, "é", "e", 0 as int32);
	} else if (i === 11) {
		resetStep("IME preedit and commit");
		ipMarked(root, "日本", 1 as int32);
		ipMarked(root, "😀x", 3 as int32);
		ipCommit(root, "日本語");
	}
}

function verify(root: Ptr<void>, i: int32): void {
	if (i === 0) {
		check(`focus true received (${focusTrue})`, focusTrue > 0);
		check(`resize ${lastW}x${lastH} == ${1100.0 * scale}x${640.0 * scale}`,
		      resizes > 0 && (lastW as float64) === 1100.0 * scale && (lastH as float64) === 640.0 * scale);
	} else if (i === 1) {
		check(`host click '${clicks}' == 'panel 200,120 b1'`, clicks === "panel 200,120 b1 ");
	} else if (i === 2) {
		check(`host click '${clicks}' == 'badge 980,44 b1'`, clicks === "badge 980,44 b1 ");
		check(`page got no click ('${pageClicks}')`, pageClicks === "");
	} else if (i === 3) {
		const want = `${((700 - 480) as float64 / scale) as int32},${((260 - 24) as float64 / scale) as int32}`;
		check(`host saw the click on the webview ('${clicks}')`, clicks === "webview 700,260 b1 ");
		check(`page click '${pageClicks}' == '${want}' (CSS px)`, pageClicks === want);
		check("webview is first responder", ipWebviewIsFirstResponder(root) !== (0 as int32));
	} else if (i === 4) {
		check(`page key '${pageKeys}' == 'KeyB'`, pageKeys === "KeyB");
		check(`host got no key ('${keys}')`, keys === "");
	} else if (i === 5) {
		check(`host click '${clicks}' == 'panel 200,120 b1 shift'`, clicks === "panel 200,120 b1 shift ");
		check("content is first responder again", ipWebviewIsFirstResponder(root) === (0 as int32));
	} else if (i === 6) {
		check(`key '${keys}' == 'KeyA:a'`, keys === "KeyA:a ");
		check(`text '${texts}' == ''`, texts === "");
	} else if (i === 7) {
		check(`key '${keys}' == 'KeyA:A shift consumed-shift'`, keys === "KeyA:A shift consumed-shift ");
	} else if (i === 8) {
		check(`key '${keys}' == 'Enter:'`, keys === "Enter: ");
		check(`text '${texts}' == ''`, texts === "");
	} else if (i === 9) {
		check(`key '${keys}' == 'KeyC:'`, keys === "KeyC: ");
		check(`text '${texts}' == ''`, texts === "");
	} else if (i === 10) {
		check(`key '${keys}' == 'KeyE:é'`, keys === "KeyE:é ");
	} else if (i === 11) {
		check(`preedit '${preedits}' == '日本@1 😀x@3 @0'`, preedits === "日本@1 😀x@3 @0 ");
		check(`text '${texts}' == '日本語'`, texts === "日本語 ");
	}
}

function step(win: Window, root: Ptr<void>, i: int32): void {
	if (i > (11 as int32)) {
		console.log(failures === 0 ? "contentInputMacos: all PASS" : `contentInputMacos: ${failures} FAIL`);
		closeWindow(win);
		return;
	}
	act(root, i);
	setTimeout((): void => {
		verify(root, i);
		step(win, root, (i + 1) as int32);
	}, STEP_MS);
}

function main(): int32 {
	const created = createWindow("main", defaultOptions("Ion content input", 1100 as int32, 640 as int32));
	if (created === null) {
		console.log("contentInputMacos: no window");
		return 1;
	}
	const win: Window = created;
	const opened = createWebview(win, "page", PAGE);
	if (opened === null) {
		console.log("contentInputMacos: no webview");
		return 1;
	}
	const web: Webview = opened;
	const root = windowRoot(win);
	const device = windowDevice(win);
	const panel = contentPanel(device, panelRect.w, panelRect.h, "native panel", 0x2f6fdb as uint32);
	const badge = contentPanel(device, badgeRect.w, badgeRect.h, "native badge", 0xd2452f as uint32);
	contentAttach(root, panel, 1 as int32);
	contentAttach(root, webviewNode(web), 1 as int32);
	contentAttach(root, badge, 1 as int32);
	contentMove(panel, panelRect.x, panelRect.y, panelRect.w, panelRect.h);
	contentMove(badge, badgeRect.x, badgeRect.y, badgeRect.w, badgeRect.h);
	setWebviewBounds(web, webRect.x, webRect.y, webRect.w, webRect.h);
	commit(win);

	onPointer((e: PointerEvent): void => {
		const hit = hitName(e.x, e.y);
		if (e.kind !== PointerKind.Button || !e.pressed) return;
		const shift = e.mods.has(KeyMod.Shift) ? " shift" : "";
		clicks += `${hit} ${e.x as int32},${e.y as int32} b${e.button}${shift} `;
		if (hit === "webview") focusWebview(web);
		else focusContent(win);
	});
	onKey((e: KeyEvent): void => {
		if (e.action === KeyAction.Release) return;
		if (keyName(e.key).startsWith("Shift") || keyName(e.key).startsWith("Control")) return;
		const shift = e.mods.has(KeyMod.Shift) ? " shift" : "";
		const consumed = e.consumedMods.has(KeyMod.Shift) ? " consumed-shift" : "";
		keys += `${keyName(e.key)}:${e.text}${shift}${consumed} `;
	});
	onText((window: int32, text: string): void => { texts += `${text} `; });
	onImePreedit((window: int32, text: string, cursor: int32): void => { preedits += `${text}@${cursor} `; });
	onFocus((window: int32, focused: boolean): void => { if (focused) focusTrue += 1; });
	onResize((window: int32, w: int32, h: int32, s: float64): void => {
		resizes += 1;
		lastW = w;
		lastH = h;
		scale = s;
	});
	listen((name: string, payload: string): void => {
		if (name === "webview.click") pageClicks += payload;
		if (name === "webview.key") pageKeys += payload;
	});

	setTimeout((): void => { step(win, root, 0 as int32); }, 800);
	runLoop();
	return failures === 0 ? 0 : 1;
}

exit(main());
