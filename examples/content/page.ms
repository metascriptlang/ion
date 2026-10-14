import {
	createWindow, defaultOptions, windowRoot, commit,
	createWebview, webviewNode, setWebviewBounds, focusWebview, forwardPointer,
	onPointer, onResize, PointerEvent, PointerKind, Webview, Window,
	PointerMove, PointerDown, PointerUp, PointerWheel, PointerHWheel, PointerLeave,
} from "../../src/index";
import { contentAttach, contentMove } from "./content";

export struct Page {
	window: Window;
	webview: Webview;
}

function pointerKind(e: PointerEvent): int32 {
	return match (e.kind) {
		PointerKind.Button => e.pressed ? PointerDown : PointerUp,
		PointerKind.Motion => PointerMove,
		PointerKind.Wheel => e.dx !== 0.0 ? PointerHWheel : PointerWheel,
		PointerKind.Leave => PointerLeave,
	};
}

export function openPage(title: string, width: int32, height: int32, label: string, url: string): Page | null {
	const created = createWindow("main", defaultOptions(title, width, height));
	if (created === null) return null as unknown as Page | null;
	const win: Window = created;
	const opened = createWebview(win, label, url);
	if (opened === null) return null as unknown as Page | null;
	const web: Webview = opened;
	contentAttach(windowRoot(win), webviewNode(web), 1 as int32);
	onResize((window: int32, w: int32, h: int32, scale: float64): void => {
		if (window !== win.id) return;
		contentMove(webviewNode(web), 0 as int32, 0 as int32, w, h);
		setWebviewBounds(web, 0 as int32, 0 as int32, w, h);
		commit(win);
	});
	onPointer((e: PointerEvent): void => {
		if (e.window !== win.id) return;
		const delta = e.dx !== 0.0 ? e.dx : e.dy;
		forwardPointer(web, pointerKind(e), e.x, e.y, e.button, delta);
		if (e.kind === PointerKind.Button && e.pressed) focusWebview(web);
	});
	focusWebview(web);
	return { window: win, webview: web } as Page | null;
}
