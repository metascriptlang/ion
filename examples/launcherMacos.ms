// A launcher beside a board window, as Raycast or Ghostty's quick terminal: a global hotkey
// summons it while another app is in front, it takes typed keys at once, and Escape or a click
// into another app dismisses it. Measures what the app sees and what the person sees:
// the key window, the frontmost app, and whether the board window was pulled above the other app.
// Needs Accessibility for the posted keys (lpTrusted); without it the hotkey and typing steps
// report SKIP. Run from a terminal: out/debug/launcherMacos.

import {
	createWindow, defaultOptions, closeWindow, runLoop, show, hide, focus, windowRoot, Window,
	listen, onKey, onWindowEvent, keyName, KeyAction,
	tryRegisterHotkeyKey, unregisterHotkey, HotkeyResult, ModCmd, ModAlt, ModCtrl,
	WindowEventBlurred,
} from "../src/index";
import { exit, env } from "std/process";

when (macos) {
	@compile("./launcherProbeMacos.m", "-fobjc-arc");
	@passL("-framework ApplicationServices");
}
@include("./launcherProbeMacos.h");

extern function lpFrontApp(): cstring;
extern function lpRememberFront(): void;
extern function lpAboveRemembered(root: Ptr<void>): int32;
extern function lpOnScreen(root: Ptr<void>): int32;
extern function lpKeyState(root: Ptr<void>): int32;
extern function lpPostKey(keyCode: int32, command: int32, option: int32, control: int32): void;
extern function lpTrusted(): int32;
extern function lpConfigure(root: Ptr<void>, mode: cstring): void;
extern function lpFocusPanel(root: Ptr<void>): void;
extern function lpSpawn(role: cstring): void;
extern function lpClickRemembered(): void;
extern function lpRememberedInFront(): int32;
extern function lpFrontIsOther(): int32;
extern function lpOnActiveSpace(root: Ptr<void>): int32;

const HOTKEY_ID: int32 = 77 as int32;
const KEY_L: int32 = 0x25 as int32;
const KEY_A: int32 = 0x00 as int32;
const KEY_B: int32 = 0x0B as int32;
const KEY_ESCAPE: int32 = 0x35 as int32;

let failures = 0;
let summons = 0;
let typed = "";
let launcherVisible = false;

function report(name: string, ok: boolean, detail: string): void {
	console.log(`${ok ? "PASS" : "FAIL"} ${name}: ${detail}`);
	if (!ok) failures += 1;
}

function front(): string { return lpFrontApp() as string; }

// The other app, a second process of this executable: a plain window in front for 7 s, or a
// fullscreen window in its own Space for 5 s.
function otherApp(fullscreen: boolean): int32 {
	const opt = defaultOptions("Ion other app", 800 as int32, 600 as int32);
	opt.fullscreen = fullscreen;
	const created = createWindow("other", opt);
	if (created === null) return 1;
	const other: Window = created;
	focus(other);
	setTimeout((): void => { closeWindow(other); }, fullscreen ? 5000 : 7000);
	runLoop();
	return 0;
}

function main(): int32 {
	if (env.get("LAUNCHER_ROLE") == "fullscreen") return otherApp(true);
	if (env.get("LAUNCHER_ROLE") == "plain") return otherApp(false);
	const boardOpt = defaultOptions("Ion board", 640 as int32, 420 as int32);
	const board = createWindow("board", boardOpt);
	const launcherOpt = defaultOptions("Ion launcher", 560 as int32, 72 as int32);
	launcherOpt.decorations = false;
	launcherOpt.alwaysOnTop = true;
	launcherOpt.visible = false;
	launcherOpt.center = true;
	launcherOpt.resizable = false;
	launcherOpt.panel = env.get("LAUNCHER_MODE") == "ion-panel";
	const created = createWindow("launcher", launcherOpt);
	if (board === null || created === null) {
		console.log("launcherMacos: no window");
		return 1;
	}
	const launcher: Window = created;
	const boardWin: Window = board;
	const mode = env.get("LAUNCHER_MODE") ?? "";
	lpConfigure(windowRoot(launcher), mode);
	console.log(`launcherMacos: mode "${mode}"`);
	const trusted = lpTrusted() === (1 as int32);
	console.log(`launcherMacos: accessibility ${trusted ? "granted" : "missing"}`);

	const summon = (): void => {
		summons += 1;
		launcherVisible = true;
		show(launcher);
		if (mode === "panel") lpFocusPanel(windowRoot(launcher));
		else focus(launcher);
	};
	const dismiss = (): void => {
		launcherVisible = false;
		hide(launcher);
	};
	const registered = tryRegisterHotkeyKey(ModCmd | ModAlt | ModCtrl, "L", HOTKEY_ID);
	report("hotkey registers", registered === HotkeyResult.Ok, `result ${registered as int32}`);
	listen((name: string, payload: string): void => {
		if (name === "hotkey" && payload === `${HOTKEY_ID}`) summon();
	});
	onKey((e): void => {
		if (e.window !== launcher.id || e.action !== KeyAction.Press) return;
		if (keyName(e.key) === "Escape") dismiss();
		else typed += e.text;
	});
	onWindowEvent((label: string, type: int32): void => {
		if (label === "launcher" && type === WindowEventBlurred && launcherVisible) dismiss();
	});

	setTimeout((): void => { lpSpawn("plain"); }, 500);
	setTimeout((): void => {
		lpRememberFront();
		report("another app is in front before the hotkey", lpFrontIsOther() === (1 as int32), front());
		if (trusted) lpPostKey(KEY_L, 1 as int32, 1 as int32, 1 as int32);
		else summon();
	}, 2200);
	setTimeout((): void => {
		const root = windowRoot(launcher);
		report("the hotkey summons the launcher", summons === 1 && lpOnScreen(root) === (1 as int32), `summons ${summons}${trusted ? "" : " (SKIP: called directly)"}`);
		report("the launcher is the key window", lpKeyState(root) >= (1 as int32), `key state ${lpKeyState(root)}`);
		report("the board stays behind the other app's windows", lpAboveRemembered(windowRoot(boardWin)) === (0 as int32), `front app ${front()}, board above the other app ${lpAboveRemembered(windowRoot(boardWin))}`);
		if (trusted) {
			lpPostKey(KEY_A, 0 as int32, 0 as int32, 0 as int32);
			lpPostKey(KEY_B, 0 as int32, 0 as int32, 0 as int32);
		}
	}, 3000);
	setTimeout((): void => {
		if (trusted) report("typed keys reach the launcher at once", typed === "ab", `typed "${typed}"`);
		else console.log("SKIP typed keys: no accessibility");
		if (trusted) lpPostKey(KEY_ESCAPE, 0 as int32, 0 as int32, 0 as int32);
		else dismiss();
	}, 3600);
	setTimeout((): void => {
		report("Escape hides the launcher", lpOnScreen(windowRoot(launcher)) === (0 as int32) && lpOnScreen(windowRoot(boardWin)) === (1 as int32), "board still open");
		report("the other app is in front again after Escape", lpRememberedInFront() === (1 as int32), front());
		summon();
	}, 4300);
	setTimeout((): void => { if (trusted) lpClickRemembered(); }, 5000);
	setTimeout((): void => {
		if (trusted) report("a click into another app hides the launcher", lpOnScreen(windowRoot(launcher)) === (0 as int32), `front app ${front()}`);
		else console.log("SKIP click into another app: no accessibility");
		lpSpawn("fullscreen");
	}, 6200);
	setTimeout((): void => {
		lpRememberFront();
		report("another app is in front in its fullscreen Space", lpFrontIsOther() === (1 as int32) && lpOnActiveSpace(windowRoot(boardWin)) === (0 as int32), `front other ${lpFrontIsOther()}, board on active space ${lpOnActiveSpace(windowRoot(boardWin))}`);
		if (trusted) lpPostKey(KEY_L, 1 as int32, 1 as int32, 1 as int32);
		else summon();
	}, 9200);
	setTimeout((): void => {
		const root = windowRoot(launcher);
		report("the launcher shows over the fullscreen app, in its Space", lpOnScreen(root) === (1 as int32) && lpOnActiveSpace(root) === (1 as int32) && lpOnActiveSpace(windowRoot(boardWin)) === (0 as int32),
			`launcher on screen ${lpOnScreen(root)}, on active space ${lpOnActiveSpace(root)}, board on active space ${lpOnActiveSpace(windowRoot(boardWin))}`);
		dismiss();
	}, 10200);
	setTimeout((): void => {
		unregisterHotkey(HOTKEY_ID);
		closeWindow(launcher);
		closeWindow(boardWin);
	}, 15500);

	runLoop();
	console.log(failures === 0 ? "launcherMacos: all PASS" : `launcherMacos: ${failures} FAIL`);
	return failures === 0 ? 0 : 1;
}

exit(main());
