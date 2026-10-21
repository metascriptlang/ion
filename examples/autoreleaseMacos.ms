import { createWindow, defaultOptions, onWake, runLoop, closeWindow } from "../src/index";
import { exit } from "std/process";

@compile("./autoreleaseMacos.c");
@include("./autoreleaseMacos.h");

extern function autoreleaseWakeFlood(ms: int32): void;
extern function autoreleaseBlocksInUse(): int32;

const FLOOD_MS: int32 = 6000 as int32;
const SETTLE_MS = 2000;
const MAX_GROWTH: int32 = 5000 as int32;

let wakes = 0;
let settled: int32 = 0 as int32;
const win = createWindow("main", defaultOptions("autoreleaseMacos", 400 as int32, 300 as int32));
onWake((): void => { wakes = wakes + 1; });
autoreleaseWakeFlood(FLOOD_MS);
setTimeout((): void => { settled = autoreleaseBlocksInUse(); }, SETTLE_MS);
setTimeout((): void => {
	const growth = (autoreleaseBlocksInUse() - settled) as int32;
	const ok = wakes > 1000 && growth < MAX_GROWTH;
	console.log(`${ok ? "PASS" : "FAIL"} autoreleaseMacos: ${wakes} wakes, ${growth} malloc blocks gained over the last ${FLOOD_MS - SETTLE_MS} ms`);
	if (win !== null) closeWindow(win);
	exit(ok ? 0 : 1);
}, FLOOD_MS);
runLoop();
