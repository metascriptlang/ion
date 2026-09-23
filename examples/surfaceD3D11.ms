// Windows render-surface demo: a D3D11 clear colour on a BELOW surface, a
// transparent webview panel framed over it, and every surface input event
// printed to stdout. Run from a console so stdout is visible:
//   msc build examples/surfaceD3D11.ms && out/debug/surfaceD3D11.exe
// WebView2Loader.dll must sit next to the exe (vendor/webview2/runtime/x64/).

import {
	createWindow, defaultOptions, runLoop, onFrame, listen,
	renderSurfaceCreate, renderSurfaceAttachSwapChain, renderSurfaceSetImeRect,
	webviewSetFrame, onInput, onKey, onText, onImePreedit, onSurfaceFocus, onSurfaceResize,
	keyName, KeyEvent, SurfaceBelow, RenderSurfaceInvalid,
} from "../src/index";
import { Window } from "../src/windowManager";
import { exit } from "std/process";

when (windows) {
	@compile("./surfaceD3D11/d3d.c");
	@include("./surfaceD3D11/d3d.h");
	@passL("-ld3d11");
	@passL("-ldxgi");
}

extern function demoD3DCreate(width: int32, height: int32): int64;
extern function demoD3DResize(width: int32, height: int32): void;
extern function demoD3DClear(r: float64, g: float64, b: float64): void;

const PANEL = "data:text/html,<body style='margin:0;background:transparent;font:14px sans-serif'>"
	+ "<div style='margin:12px;padding:12px;border-radius:8px;background:rgba(255,255,255,0.75)'>"
	+ "webview panel over the D3D11 surface<br><input placeholder='type here: goes to the webview'>"
	+ "<div id=drop style='margin-top:6px'>drop files here</div>"
	+ "</div><script>addEventListener('dragover',e=>e.preventDefault());"
	+ "addEventListener('pointerdown',e=>{document.getElementById('drop').textContent="
	+ "'pointer: '+e.pointerType+' at '+e.clientX+','+e.clientY+' pressure '+e.pressure.toFixed(2)});"
	+ "addEventListener('drop',e=>{e.preventDefault();document.getElementById('drop').textContent="
	+ "'dropped: '+[...e.dataTransfer.files].map(f=>f.name).join(', ')})</script></body>";

function visible(text: string): string {
	let control = false;
	for (let i = 0; i < text.length; i++) {
		if (text.charCodeAt(i) < 32) control = true;
	}
	if (!control) return text;
	let out = "";
	for (let i = 0; i < text.length; i++) {
		const c = text.charCodeAt(i);
		if (c < 32) out += `\\x${c.toString(16)}`;
		else out += text.charAt(i);
	}
	return out;
}

let _swapChain: int64 = 0 as int64;
let _window: Window | null = null;

function px(logical: int32, scale: float64): int32 {
	return ((logical as float64) * scale) as int32;
}

function onResize(surface: int32, width: int32, height: int32, scale: float64): void {
	console.log(`resize surface=${surface} ${width}x${height} scale=${scale}`);
	if (_swapChain === (0 as int64)) {
		_swapChain = demoD3DCreate(width, height);
		const attached = renderSurfaceAttachSwapChain(surface, _swapChain);
		console.log(`attach swapchain=${attached}`);
	} else {
		demoD3DResize(width, height);
	}
	renderSurfaceSetImeRect(surface, px(40 as int32, scale), height - px(80 as int32, scale), px(8 as int32, scale), px(20 as int32, scale));
	if (_window !== null) {
		webviewSetFrame(_window, px(20 as int32, scale), px(20 as int32, scale), px(420 as int32, scale), px(140 as int32, scale));
	}
}

function onKeyEvent(e: KeyEvent): void {
	console.log(`key ${e.action.toString()} ${keyName(e.key)} scancode=0x${e.scancode.toString(16)} `
		+ `mods=${e.mods.toString()} consumed=${e.consumedMods.toString()} `
		+ `unshifted=${e.unshifted} text="${visible(e.text)}"`);
}

function main(): int32 {
	const win = createWindow("main", defaultOptions("Ion surface D3D11", 900 as int32, 600 as int32, PANEL));
	if (win === null) return 1;
	_window = win;
	const surf = renderSurfaceCreate(win, SurfaceBelow);
	if (surf === RenderSurfaceInvalid) return 2;

	onSurfaceResize(onResize);
	onKey(onKeyEvent);
	onText((surface: int32, text: string): void => { console.log(`text surface=${surface} "${visible(text)}"`); });
	onImePreedit((surface: int32, text: string, cursor: int32): void => {
		console.log(`preedit surface=${surface} "${text}" cursor=${cursor}`);
	});
	onSurfaceFocus((surface: int32, focused: boolean): void => {
		console.log(`focus surface=${surface} ${focused ? "gained" : "lost"}`);
	});
	onInput((type: int32, x: float64, y: float64, p1: float64, p2: float64): void => {
		console.log(`pointer type=${type} x=${x} y=${y} p1=${p1} p2=${p2}`);
	});
	listen((name: string, payload: string): void => { console.log(`ipc ${name} ${payload}`); });
	onFrame((): void => { demoD3DClear(0.05, 0.25, 0.30); });

	runLoop();
	return 0;
}

exit(main());
