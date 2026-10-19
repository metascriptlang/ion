import {
	createWindow, closeWindow, windowCount, defaultOptions, windowRoot, listen, messageWebviewId, runLoop,
	setAppMenu, MenuItem, MenuRole, Submenu, ModCmd, Window,
} from "../src/index";
import { env, exit } from "std/process";

when (macos) {
	@compile("./inputProbeMacos.m", "-fobjc-arc");
	@passL("-framework WebKit");
}
@include("./inputProbeMacos.h");

extern function ipActivate(root: Ptr<void>): void;
extern function ipKey(root: Ptr<void>, keyCode: int32, chars: cstring, bare: cstring, mods: int32): void;

const KEY_W: int32 = 0x0D as int32;
const ION_MOD_SUPER: int32 = 8 as int32;
const beforeWindow = env.get("MENU_BEFORE_WINDOW") === "1";

let failures = 0;
let clicks = "";
let clickWebview: int32 = 0 as int32;

function check(name: string, ok: boolean): void {
	console.log(`${ok ? "PASS" : "FAIL"} ${name}`);
	if (!ok) failures += 1;
}

function open(label: string): Window {
	const created = createWindow(label, defaultOptions(`Ion menu ${label}`, 360 as int32, 240 as int32));
	if (created === null) {
		console.log(`menuMacos: no window ${label}`);
		exit(1);
	}
	return created as Window;
}

function commandW(win: Window): void {
	ipActivate(windowRoot(win));
	ipKey(windowRoot(win), KEY_W, "w", "w", ION_MOD_SUPER);
}

function appBar(): Submenu[] {
	return [
		{ title: "", items: [MenuItem.standard(MenuRole.Hide), MenuItem.separator(), MenuItem.standard(MenuRole.Quit)] },
		{ title: "File", items: [MenuItem.action("close_window", "Close Window", "w", ModCmd)] },
	];
}

function declared(menus: Submenu[]): boolean {
	const r = setAppMenu(menus);
	if (!r.ok) console.log(r.error);
	return r.ok;
}

function after(ms: number, then: () => void): void {
	setTimeout((): void => { then(); }, ms);
}

function main(): int32 {
	listen((name: string, payload: string): void => {
		if (name !== "menu.click") return;
		clicks += payload + ";";
		clickWebview = messageWebviewId();
	});
	if (beforeWindow) check("app bar declared before the first window", declared(appBar()));
	const main = open("main");
	const second = open("second");

	after(800, (): void => { commandW(second); });
	after(1600, (): void => {
		if (beforeWindow) {
			check(`Cmd+W on the app bar delivers menu.click close_window (${clicks})`, clicks === "close_window;");
			check(`menu.click comes from no webview (${clickWebview})`, clickWebview === (-1 as int32));
			check(`the window stays open (${windowCount()} windows)`, windowCount() === (2 as int32));
			closeWindow(second);
			closeWindow(main);
			return;
		}
		check(`Cmd+W on Ion's default bar closes the key window (${windowCount()} left)`, windowCount() === (1 as int32));
		check("app bar declared", declared(appBar()));
		commandW(main);
	});
	after(2400, (): void => {
		if (beforeWindow) return;
		check(`Cmd+W on the app bar delivers menu.click close_window (${clicks})`, clicks === "close_window;");
		check(`the window stays open (${windowCount()} windows)`, windowCount() === (1 as int32));
		const bad = setAppMenu([{ title: "File", items: [MenuItem.action("x", "Bad", "Hyper", ModCmd)] }]);
		check(`an unknown key is refused by name (${bad.ok ? "ok" : bad.error})`, !bad.ok && bad.error.includes("'Hyper'"));
		commandW(main);
	});
	after(3200, (): void => {
		if (beforeWindow) return;
		check(`the refused bar left the app bar in place (${clicks})`, clicks === "close_window;close_window;");
		check("bar replaced with the CloseWindow role", declared([{ title: "File", items: [MenuItem.standard(MenuRole.CloseWindow)] }]));
		const third = open("third");
		after(400, (): void => { commandW(third); });
	});
	after(4400, (): void => {
		if (beforeWindow) return;
		check(`Cmd+W on the replaced bar closes the key window (${windowCount()} left)`, windowCount() === (1 as int32));
		closeWindow(main);
	});

	runLoop();
	check(`closeWindow from the app closed every window (${windowCount()} left)`, windowCount() === (0 as int32));
	console.log(failures === 0 ? "menuMacos: all PASS" : `menuMacos: ${failures} FAIL`);
	return failures === 0 ? 0 : 1;
}

exit(main());
