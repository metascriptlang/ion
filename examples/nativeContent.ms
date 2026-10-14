// WebView2Loader.dll must sit next to the exe (vendor/webview2/runtime/x64/).

import {
	createWindow, defaultOptions, windowRoot, windowDevice, commit, focusContent, setCursor,
	createWebview, webviewNode, setWebviewBounds, focusWebview, forwardPointer, listen, runLoop,
	onPointer, onKey, onResize, onFocus, keyName,
	PointerEvent, PointerKind, KeyEvent, KeyAction, Webview, Window,
	PointerMove, PointerDown, PointerUp, PointerWheel, PointerHWheel, PointerLeave,
	CursorArrow, CursorHand,
} from "../src/index";
import { contentAttach, contentMove, contentPanel } from "./content/content";
import { exit } from "std/process";

const PAGE = "data:text/html,<body style='margin:0;font:16px sans-serif;background:%23f4f4f4'>"
	+ "<div style='padding:24px'>webview, a child of the app's tree<br><br>"
	+ "<input id=box placeholder='type here: goes to the webview'></div>"
	+ "<script>addEventListener('pointerdown',e=>window.__ion__.post('webview.click',e.clientX+','+e.clientY));"
	+ "addEventListener('keydown',e=>window.__ion__.post('webview.key',e.code))</script></body>";

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

enum Hit {
	None,
	Panel,
	Webview,
	Badge,
}

function pointerKind(e: PointerEvent): int32 {
	return match (e.kind) {
		PointerKind.Button => e.pressed ? PointerDown : PointerUp,
		PointerKind.Motion => PointerMove,
		PointerKind.Wheel => e.dx !== 0.0 ? PointerHWheel : PointerWheel,
		PointerKind.Leave => PointerLeave,
	};
}

function hitName(hit: Hit): string {
	return match (hit) {
		Hit.None => "background",
		Hit.Panel => "panel",
		Hit.Webview => "webview",
		Hit.Badge => "badge",
	};
}

function main(): int32 {
	const created = createWindow("main", defaultOptions("Ion content root", 1100 as int32, 640 as int32));
	if (created === null) {
		console.log("nativeContent: no window");
		return 1;
	}
	const win: Window = created;
	const opened = createWebview(win, "page", PAGE);
	if (opened === null) {
		console.log("nativeContent: no webview");
		return 1;
	}
	const web: Webview = opened;

	const panelRect: Rect = { x: 24 as int32, y: 24 as int32, w: 420 as int32, h: 220 as int32 };
	const webRect: Rect = { x: 480 as int32, y: 24 as int32, w: 560 as int32, h: 520 as int32 };
	const badgeRect: Rect = { x: 900 as int32, y: 12 as int32, w: 160 as int32, h: 64 as int32 };

	const root = windowRoot(win);
	const device = windowDevice(win);
	const panel = contentPanel(device, panelRect.w, panelRect.h, "native D2D panel", 0x2f6fdb as uint32);
	const badge = contentPanel(device, badgeRect.w, badgeRect.h, "native badge", 0xd2452f as uint32);
	contentAttach(root, panel, 1 as int32);
	contentAttach(root, webviewNode(web), 1 as int32);
	contentAttach(root, badge, 1 as int32);
	contentMove(panel, panelRect.x, panelRect.y, panelRect.w, panelRect.h);
	contentMove(webviewNode(web), webRect.x, webRect.y, webRect.w, webRect.h);
	contentMove(badge, badgeRect.x, badgeRect.y, badgeRect.w, badgeRect.h);
	setWebviewBounds(web, webRect.x, webRect.y, webRect.w, webRect.h);
	commit(win);

	let hover = Hit.None;
	const hitAt = (x: float64, y: float64): Hit => {
		if (inside(badgeRect, x, y)) return Hit.Badge;
		if (inside(webRect, x, y)) return Hit.Webview;
		if (inside(panelRect, x, y)) return Hit.Panel;
		return Hit.None;
	};

	onPointer((e: PointerEvent): void => {
		const hit = e.kind === PointerKind.Leave ? Hit.None : hitAt(e.x, e.y);
		if (hover === Hit.Webview && hit !== Hit.Webview) {
			forwardPointer(web, PointerLeave, 0.0, 0.0, 0 as int32, 0.0);
		}
		if (hit !== hover) setCursor(win, hit === Hit.Badge ? CursorHand : CursorArrow);
		hover = hit;
		if (hit === Hit.Webview) {
			const delta = e.dx !== 0.0 ? e.dx : e.dy;
			forwardPointer(web, pointerKind(e), e.x - (webRect.x as float64), e.y - (webRect.y as float64), e.button, delta);
			if (e.kind === PointerKind.Button && e.pressed) focusWebview(web);
			return;
		}
		if (e.kind === PointerKind.Button && e.pressed) {
			focusContent(win);
			console.log(`host click: ${hitName(hit)} at ${e.x as int32},${e.y as int32} button ${e.button}`);
		}
	});
	onKey((e: KeyEvent): void => {
		if (e.action === KeyAction.Release) return;
		console.log(`host key: ${keyName(e.key)} text '${e.text}'`);
	});
	onFocus((window: int32, focused: boolean): void => {
		console.log(`host focus: ${focused}`);
	});
	onResize((window: int32, w: int32, h: int32, scale: float64): void => {
		console.log(`host resize: ${w}x${h} scale ${scale}`);
	});
	listen((name: string, payload: string): void => {
		if (name === "webview.click" || name === "webview.key") console.log(`${name}: ${payload}`);
	});

	runLoop();
	return 0;
}

exit(main());
