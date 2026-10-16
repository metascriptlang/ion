import {
	createWindow, defaultOptions, runLoop, onPointer, PointerEvent, PointerKind, KeyMod,
} from "../src/index";
import { exit } from "std/process";

@compile("./pointerMods.c");
@include("./pointerMods.h");

extern function pmClick(shift: int32, x: int32, y: int32): void;
extern function pmClose(): void;

const STEP_MS = 100;

let failures: int32 = 0 as int32;
let seen = 0;
let shiftSeen = 0;

function check(what: string, ok: boolean): void {
	if (!ok) failures = (failures + 1) as int32;
	console.log(`${ok ? "PASS" : "FAIL"} ${what}`);
}

function clickWith(shift: boolean, then: () => void): void {
	seen = 0;
	shiftSeen = 0;
	pmClick(shift ? 1 as int32 : 0 as int32, 40 as int32, 30 as int32);
	setTimeout(then, STEP_MS);
}

function main(): int32 {
	const created = createWindow("main", defaultOptions("Ion pointer mods", 320 as int32, 200 as int32));
	if (created === null) {
		console.log("pointerMods: no window");
		return 1;
	}
	onPointer((e: PointerEvent): void => {
		if (e.kind !== PointerKind.Button && e.kind !== PointerKind.Motion) return;
		seen++;
		if (e.mods.has(KeyMod.Shift)) shiftSeen++;
	});
	setTimeout((): void => {
		clickWith(true, (): void => {
			check(`Shift held: ${seen} pointer events, ${shiftSeen} with Shift`, seen >= 3 && shiftSeen === seen);
			clickWith(false, (): void => {
				check(`Shift released: ${seen} pointer events, ${shiftSeen} with Shift`, seen >= 3 && shiftSeen === 0);
				console.log(failures === (0 as int32) ? "pointerMods: all PASS" : `pointerMods: ${failures} FAIL`);
				pmClose();
			});
		});
	}, STEP_MS);
	runLoop();
	return failures === (0 as int32) ? 0 : 1;
}

exit(main());
