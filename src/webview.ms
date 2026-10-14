import {
	ionWebviewCreate, ionWebviewRelease, ionFindWebview, ionWebviewLabel, ionWebviewWindow,
	ionWebviewNode, ionWebviewSetBounds, ionWebviewSetVisible, ionWebviewSetTransparent,
	ionWebviewNavigate, ionWebviewEval, ionWebviewFocus, ionWebviewForwardPointer,
	ionResourcePath, ionRegisterStaticProtocol,
} from "./platform/bridge.h";
import { Window } from "./windowManager";
import { jsEscape } from "./internal/jsEscape";
import { parseJson } from "std/serialize/json/parser";
import { JsonKind } from "std/serialize/json/types";

export interface Webview {
	id: int32;
	label: string;
}

const MaxWebviews: int32 = 32 as int32;

export const PointerMove: int32 = 1 as int32;
export const PointerDown: int32 = 2 as int32;
export const PointerUp: int32 = 3 as int32;
export const PointerWheel: int32 = 4 as int32;
export const PointerHWheel: int32 = 5 as int32;
export const PointerLeave: int32 = 6 as int32;

let _ionSchemeChecked = false;

function serveBundledResources(url: string): void {
	if (_ionSchemeChecked || !url.startsWith("ion://")) return;
	_ionSchemeChecked = true;
	const res = ionResourcePath();
	if (res !== "") ionRegisterStaticProtocol("ion", res);
}

export function createWebview(win: Window, label: string, url: string): Webview | null {
	serveBundledResources(url);
	const id = ionWebviewCreate(win.id, label, url);
	if (id < (0 as int32)) return null as unknown as Webview | null;
	return { id, label } as Webview | null;
}

export function releaseWebview(web: Webview): void { ionWebviewRelease(web.id); }

export function getWebview(label: string): Webview | null {
	const id = ionFindWebview(label);
	if (id < (0 as int32)) return null as unknown as Webview | null;
	return { id, label } as Webview | null;
}

export function webviewById(id: int32): Webview | null {
	const label = ionWebviewLabel(id);
	if (label === "") return null as unknown as Webview | null;
	return { id, label } as Webview | null;
}

export function webviewWindowId(web: Webview): int32 { return ionWebviewWindow(web.id); }
export function webviewNode(web: Webview): Ptr<void> { return ionWebviewNode(web.id); }

export function setWebviewBounds(web: Webview, x: int32, y: int32, w: int32, h: int32): void {
	ionWebviewSetBounds(web.id, x, y, w, h);
}
export function setWebviewVisible(web: Webview, visible: boolean): void {
	ionWebviewSetVisible(web.id, visible ? (1 as int32) : (0 as int32));
}
export function setWebviewTransparent(web: Webview, transparent: boolean): void {
	ionWebviewSetTransparent(web.id, transparent ? (1 as int32) : (0 as int32));
}

export function navigate(web: Webview, url: string): void { ionWebviewNavigate(web.id, url); }
export function evalJs(web: Webview, js: string): void { ionWebviewEval(web.id, js); }
export function focusWebview(web: Webview): void { ionWebviewFocus(web.id); }

export function forwardPointer(web: Webview, kind: int32, x: float64, y: float64, button: int32, delta: float64): void {
	ionWebviewForwardPointer(web.id, kind, x, y, button, delta);
}

function dispatchJs(event: string, payload: string): string {
	return `if(window.__ion__&&window.__ion__._dispatch)window.__ion__._dispatch("${jsEscape(event)}","${jsEscape(payload)}")`;
}

export function emit(web: Webview, event: string, payload: string): void {
	ionWebviewEval(web.id, dispatchJs(event, payload));
}

export function emitTo(label: string, event: string, payload: string): void {
	const id = ionFindWebview(label);
	if (id < (0 as int32)) return;
	ionWebviewEval(id, dispatchJs(event, payload));
}

export function emitAll(event: string, payload: string): void {
	const js = dispatchJs(event, payload);
	for (let i = 0 as int32; i < MaxWebviews; i = (i + 1) as int32) {
		if (ionWebviewLabel(i) !== "") ionWebviewEval(i, js);
	}
}

export function routeEmit(envelope: string): void {
	const r = parseJson(envelope);
	if (!r.ok) return;
	const v = r.value;
	if (v.kind !== JsonKind.Object) return;
	let target = "";
	let event = "";
	let payload = "";
	for (let i = 0; i < v.keys.length; i = i + 1) {
		const k = v.keys[i];
		const val = v.values[i];
		if (val.kind !== JsonKind.String) continue;
		if      (k === "target")  target  = val.strVal;
		else if (k === "event")   event   = val.strVal;
		else if (k === "payload") payload = val.strVal;
	}
	if (target === "") emitAll(event, payload);
	else               emitTo(target, event, payload);
}
