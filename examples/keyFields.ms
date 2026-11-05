import {
	createWindow, defaultOptions, runLoop, onKey, KeyAction, KeyEvent,
} from "../src/index";
import { exit } from "std/process";

@compile("./keyFields.c");
@include("./keyFields.h");

extern function kfLayout(klid: cstring): int32;
extern function kfKey(vk: int32, ctrl: int32, shift: int32, alt: int32, altGr: int32): int32;
extern function kfUnloadLayouts(): void;
extern function kfClose(): void;

const STEP_MS = 100;
const Z: int32 = 0 as int32;
const ON: int32 = 1 as int32;

struct Case {
	name: string;
	layout: string;
	vk: int32;
	ctrl: int32;
	shift: int32;
	alt: int32;
	altGr: int32;
	text: string;
	chord: string;
	all: string;
	releaseAll: string;
}

function c(name: string, layout: string, vk: int32, ctrl: int32, shift: int32, alt: int32, altGr: int32,
	text: string, chord: string, all: string, releaseAll: string): Case {
	return { name, layout, vk, ctrl, shift, alt, altGr, text, chord, all, releaseAll };
}

const US = "00000409";
const DE = "00000407";

const cases: Case[] = [
	c("a", US, 0x41 as int32, Z, Z, Z, Z, "a", "a", "a", "a"),
	c("Ctrl+A", US, 0x41 as int32, ON, Z, Z, Z, "", "a", "\x01", "\x01"),
	c("Ctrl+C", US, 0x43 as int32, ON, Z, Z, Z, "", "c", "\x03", "\x03"),
	c("Ctrl+[", US, 0xDB as int32, ON, Z, Z, Z, "", "[", "\x1b", "\x1b"),
	c("Ctrl+Shift+-", US, 0xBD as int32, ON, ON, Z, Z, "", "_", "\x1f", "\x1f"),
	c("Ctrl+Shift+6", US, 0x36 as int32, ON, ON, Z, Z, "", "^", "\x1e", "\x1e"),
	c("Enter", US, 0x0D as int32, Z, Z, Z, Z, "", "\r", "\r", "\r"),
	c("Shift+Enter", US, 0x0D as int32, Z, ON, Z, Z, "", "\r", "\r", "\r"),
	c("Ctrl+Enter", US, 0x0D as int32, ON, Z, Z, Z, "", "\r", "\n", "\n"),
	c("Alt+Shift+.", US, 0xBE as int32, Z, ON, ON, Z, "", ">", ">", ">"),
	c("AltGr+Q (German)", DE, 0x51 as int32, Z, Z, Z, ON, "@", "@", "@", "@"),
];

let failures: int32 = 0 as int32;
const seen: KeyEvent[] = [];

function check(what: string, ok: boolean): void {
	if (!ok) failures = (failures + 1) as int32;
	console.log(`${ok ? "PASS" : "FAIL"} ${what}`);
}

function hex(s: string): string {
	let out = "";
	for (let i = 0; i < s.length; i++) out = out + (i > 0 ? " " : "") + s.charCodeAt(i).toString(16);
	return out === "" ? "(none)" : out;
}

function same(what: string, got: string, want: string): void {
	check(`${what} ${hex(got)} == ${hex(want)}`, got === want);
}

function step(i: int32): void {
	if (i >= (cases.length as int32)) {
		console.log(failures === (0 as int32) ? "keyFields: all PASS" : `keyFields: ${failures} FAIL`);
		kfClose();
		return;
	}
	const k = cases[i];
	if (kfLayout(k.layout) === Z) {
		check(`${k.name}: layout ${k.layout} loads`, false);
		step((i + 1) as int32);
		return;
	}
	seen.length = 0;
	const chars = kfKey(k.vk, k.ctrl, k.shift, k.alt, k.altGr);
	setTimeout((): void => {
		console.log(`${k.name}: ${chars} character message(s), ${seen.length} key record(s)`);
		check(`${k.name}: a press and a release`, seen.length === 2);
		if (seen.length === 2) {
			const p = seen[0];
			const r = seen[1];
			check(`${k.name}: press first`, p.action === KeyAction.Press && r.action === KeyAction.Release);
			check(`${k.name}: press vk ${p.windowsVirtualKey} == ${k.vk}`, p.windowsVirtualKey === k.vk);
			check(`${k.name}: release vk ${r.windowsVirtualKey} == ${k.vk}`, r.windowsVirtualKey === k.vk);
			same(`${k.name}: text`, p.text, k.text);
			same(`${k.name}: chordText`, p.chordText, k.chord);
			same(`${k.name}: allModsText`, p.allModsText, k.all);
			same(`${k.name}: release chordText`, r.chordText, "");
			same(`${k.name}: release allModsText`, r.allModsText, k.releaseAll);
		}
		step((i + 1) as int32);
	}, STEP_MS);
}

function main(): int32 {
	const created = createWindow("main", defaultOptions("Ion key fields", 320 as int32, 200 as int32));
	if (created === null) {
		console.log("keyFields: no window");
		return 1;
	}
	onKey((e: KeyEvent): void => { seen.push(e); });
	setTimeout((): void => step(0 as int32), STEP_MS);
	runLoop();
	kfUnloadLayouts();
	return failures === (0 as int32) ? 0 : 1;
}

exit(main());
