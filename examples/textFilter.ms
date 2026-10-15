import {
	createWindow, defaultOptions, runLoop, onText, onKey, KeyAction, KeyEvent,
} from "../src/index";
import { exit } from "std/process";

@compile("./textFilter.c");
@include("./textFilter.h");

extern function tfSend(sys: int32, unit: int32, vk: int32, ctrl: int32, alt: int32): void;
extern function tfClose(): void;

const STEP_MS = 100;

struct Case {
	name: string;
	sys: int32;
	unit: int32;
	unit2: int32;
	vk: int32;
	ctrl: int32;
	alt: int32;
	want: string;
}

function c(name: string, sys: int32, unit: int32, unit2: int32, vk: int32, ctrl: int32, alt: int32, want: string): Case {
	return { name, sys, unit, unit2, vk, ctrl, alt, want };
}

const VK_BACK: int32 = 0x08 as int32;
const VK_RETURN: int32 = 0x0D as int32;
const VK_C: int32 = 0x43 as int32;
const VK_X: int32 = 0x58 as int32;
const Z: int32 = 0 as int32;
const ON: int32 = 1 as int32;

const cases: Case[] = [
	c("Ctrl+C 0x03", Z, 0x03 as int32, Z, VK_C, ON, Z, ""),
	c("Enter 0x0D", Z, 0x0D as int32, Z, VK_RETURN, Z, Z, ""),
	c("Tab 0x09", Z, 0x09 as int32, Z, Z, Z, Z, ""),
	c("Backspace 0x08", Z, 0x08 as int32, Z, VK_BACK, Z, Z, ""),
	c("Esc 0x1B", Z, 0x1B as int32, Z, Z, Z, Z, ""),
	c("DEL 0x7F", Z, 0x7F as int32, Z, Z, Z, Z, ""),
	c("a", Z, 0x61 as int32, Z, Z, Z, Z, "a"),
	c("e acute 0xE9", Z, 0xE9 as int32, Z, Z, Z, Z, "é"),
	c("surrogate pair U+1F600", Z, 0xD83D as int32, 0xDE00 as int32, Z, Z, Z, "😀"),
	c("Ctrl+Alt (AltGr) @", Z, 0x40 as int32, Z, Z, ON, ON, "@"),
	c("Alt WM_SYSCHAR x", ON, 0x78 as int32, Z, VK_X, Z, ON, ""),
];

let failures: int32 = 0 as int32;
let texts = "";
let keyPressTexts = "";

function check(what: string, ok: boolean): void {
	if (!ok) failures = (failures + 1) as int32;
	console.log(`${ok ? "PASS" : "FAIL"} ${what}`);
}

function show(s: string): string {
	return s === "" ? "(none)" : s;
}

function step(i: int32): void {
	if (i >= (cases.length as int32)) {
		check("key record text carries no control character", keyPressTexts === "");
		console.log(failures === (0 as int32) ? "textFilter: all PASS" : `textFilter: ${failures} FAIL`);
		tfClose();
		return;
	}
	const k = cases[i];
	texts = "";
	tfSend(k.sys, k.unit, k.vk, k.ctrl, k.alt);
	if (k.unit2 !== Z) tfSend(k.sys, k.unit2, k.vk, k.ctrl, k.alt);
	setTimeout((): void => {
		check(`${k.name}: onText ${show(texts)} == ${show(k.want)}`, texts === k.want);
		step((i + 1) as int32);
	}, STEP_MS);
}

function main(): int32 {
	const created = createWindow("main", defaultOptions("Ion text filter", 320 as int32, 200 as int32));
	if (created === null) {
		console.log("textFilter: no window");
		return 1;
	}
	onText((window: int32, text: string): void => { texts = texts + text; });
	onKey((e: KeyEvent): void => {
		if (e.action === KeyAction.Press && e.text !== "") keyPressTexts = keyPressTexts + e.text;
	});
	setTimeout((): void => step(0 as int32), STEP_MS);
	runLoop();
	return failures === (0 as int32) ? 0 : 1;
}

exit(main());
