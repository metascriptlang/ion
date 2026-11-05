// Window frame, cell-step resize and background colour, read back natively (windowFrameProbe.c on
// Windows, windowFrameProbe.m on macOS). Prints PASS/FAIL lines and exits non-zero on a FAIL.
// Run: msc build examples/windowFrame.ms && out/debug/windowFrame

import {
	createWindow, closeWindow, defaultOptions, runLoop, maximize, setSize, setPosition, show,
	windowFrame, setResizeIncrements, setBackgroundColor, NoBackgroundColor, Window, WindowFrame, WindowOptions,
} from "../src/index";
import { exit } from "std/process";

when (macos) {
	@compile("./windowFrameProbe.m", "-fobjc-arc");
}
when (windows) {
	@compile("./windowFrameProbe.c");
}
@include("./windowFrameProbe.h");

extern function wpPixel(window: int32, x: int32, y: int32): int32;
extern function wpZoomed(window: int32): int32;
extern function wpVisible(window: int32): int32;
extern function wpSteps(window: int32, cellW: int32, cellH: int32, baseW: int32, baseH: int32): int32;
extern function wpOnScreen(x: int32, y: int32): int32;

const STEP_MS = 600;
const DARK: int32 = 0x1e1e2e as int32;
const BLUE: int32 = 0x336699 as int32;

let failures = 0;

function check(what: string, ok: boolean): void {
	if (!ok) failures += 1;
	console.log(`${ok ? "PASS" : "FAIL"} ${what}`);
}

function hex(rgb: int32): string {
	return rgb < (0 as int32) ? "none" : `#${rgb.toString(16)}`;
}

function describe(f: WindowFrame | null): string {
	if (f === null) return "null";
	const g: WindowFrame = f;
	return `${g.x},${g.y} ${g.width}x${g.height}${g.maximized ? " maximized" : ""}`;
}

function open(label: string, frame: WindowFrame | null, background: int32, visible: boolean): Window {
	const o: WindowOptions = { ...defaultOptions(label, 640 as int32, 360 as int32), frame, backgroundColor: background, visible };
	const created = createWindow(label, o);
	if (created === null) {
		console.log(`windowFrame: no window ${label}`);
		exit(1);
	}
	return created as Window;
}

function later(f: () => void): void {
	setTimeout(f, STEP_MS);
}

function main(): int32 {
	const plain = open("plain", null, NoBackgroundColor, true);
	const bg = open("bg", null, DARK, true);
	later((): void => {
		const p = wpPixel(plain.id, 20 as int32, 20 as int32);
		console.log(`INFO window without backgroundColor shows ${hex(p)}`);
		check(`backgroundColor ${hex(DARK)} at creation shows ${hex(wpPixel(bg.id, 20 as int32, 20 as int32))}`,
		      wpPixel(bg.id, 20 as int32, 20 as int32) === DARK);
		closeWindow(plain);
		setBackgroundColor(bg, BLUE);
		later((): void => {
			check(`setBackgroundColor ${hex(BLUE)} shows ${hex(wpPixel(bg.id, 20 as int32, 20 as int32))}`,
			      wpPixel(bg.id, 20 as int32, 20 as int32) === BLUE);
			setResizeIncrements(bg, 18 as int32, 34 as int32, 10 as int32, 6 as int32);
			check("resize steps 18x34 from base 10x6", wpSteps(bg.id, 18 as int32, 34 as int32, 10 as int32, 6 as int32) !== (0 as int32));
			setResizeIncrements(bg, 0 as int32, 0 as int32, 0 as int32, 0 as int32);
			setSize(bg, 640 as int32, 360 as int32);
			setPosition(bg, 200 as int32, 150 as int32);
			later((): void => {
				const normal = describe(windowFrame(bg));
				check(`windowFrame ${normal} == 200,150 640x360`, normal === "200,150 640x360");
				maximize(bg);
				later((): void => {
					const zoomed = describe(windowFrame(bg));
					check(`maximized windowFrame ${zoomed} == 200,150 640x360 maximized`, zoomed === "200,150 640x360 maximized");
					closeWindow(bg);
					restoreSteps();
				});
			});
		});
	});
	runLoop();
	console.log(failures === 0 ? "windowFrame: all PASS" : `windowFrame: ${failures} FAIL`);
	return failures === 0 ? 0 : 1;
}

function restoreSteps(): void {
	const saved: WindowFrame = { x: 220 as int32, y: 160 as int32, width: 600 as int32, height: 340 as int32, maximized: true };
	const restored = open("restored", saved, DARK, true);
	const hidden = open("hidden", saved, DARK, false);
	const lost: WindowFrame = { x: 100000 as int32, y: 100000 as int32, width: 500 as int32, height: 300 as int32, maximized: false };
	const moved = open("moved", lost, NoBackgroundColor, true);
	later((): void => {
		check("frame maximized at creation is maximized", wpZoomed(restored.id) !== (0 as int32));
		const back = describe(windowFrame(restored));
		check(`restored windowFrame ${back} == 220,160 600x340 maximized`, back === "220,160 600x340 maximized");
		check("hidden window stays hidden", wpVisible(hidden.id) === (0 as int32));
		const f = windowFrame(moved);
		const g: WindowFrame = f as WindowFrame;
		check(`frame on a missing monitor lands on a screen: ${describe(f)}`,
		      wpOnScreen(g.x, g.y) !== (0 as int32) && g.width === (500 as int32) && g.height === (300 as int32));
		show(hidden);
		later((): void => {
			check("hidden window restored maximized is maximized once shown", wpZoomed(hidden.id) !== (0 as int32));
			closeWindow(restored);
			closeWindow(hidden);
			closeWindow(moved);
		});
	});
}

exit(main());
