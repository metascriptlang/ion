// Multi-window MS API — Tauri-style createWindow + per-window properties +
// targeted IPC. Wraps the C bridge so apps work with strongly-typed Window
// handles instead of raw int32 ids.
//
// The v0 single-window API (`open()` / `close()` in window.ms) is unchanged
// — it goes through `ionCreateWindow("main", ...)` internally so legacy
// apps keep working unchanged. New code uses createWindow.
//
// Usage:
//
//   const main = createWindow("main", defaultOptions("MyApp",
//       1280 as int32, 800 as int32, "ion://localhost/index.html"));
//   if (main === null) return 1;
//
//   const panel = createWindow("quick-panel", {
//       title: "", width: 680 as int32, height: 420 as int32,
//       url: "ion://localhost/panel.html",
//       resizable: true, decorations: false,
//       alwaysOnTop: true, transparent: false,
//       visible: false, center: true,
//       x: 0 as int32, y: 0 as int32,
//   });

import {
    ionInit, ionCreateWindow, ionCloseWindow, ionWindowCount, ionFindWindow,
    ionShowWindow, ionHideWindow, ionFocusWindow,
    ionMinimizeWindow, ionMaximizeWindow,
    ionSetWindowTitle, ionSetWindowSize, ionSetWindowPosition,
    ionSetWindowAlwaysOnTop, ionSetWindowDecorations,
    ionSetWindowContentProtected,
    ionWindowPixelWidth, ionWindowPixelHeight,
    ionEvalJSWindow, ionFileOpenWindow,
} from "./platform/bridge.h";
import { jsEscape } from "./internal/jsEscape";
import { parseJson } from "std/serialize/json/parser";
import { JsonKind } from "std/serialize/json/types";

// ---- Window flags (mirror bridge.h) ---------------------------------------

const ION_WIN_RESIZABLE:     int32 = 1 as int32;
const ION_WIN_DECORATIONS:   int32 = 2 as int32;
const ION_WIN_ALWAYS_ON_TOP: int32 = 4 as int32;
const ION_WIN_TRANSPARENT:   int32 = 8 as int32;
const ION_WIN_VISIBLE:       int32 = 16 as int32;
const ION_WIN_CENTERED:      int32 = 32 as int32;
const ION_WIN_FULLSCREEN:    int32 = 64 as int32;

// ---- Window event types (mirror common/windowEvents.h) --------------------

export const WindowEventCloseRequested: int32 = 1 as int32;
export const WindowEventDestroyed:      int32 = 2 as int32;
export const WindowEventFocused:        int32 = 3 as int32;
export const WindowEventBlurred:        int32 = 4 as int32;
export const WindowEventResized:        int32 = 5 as int32;
export const WindowEventMoved:          int32 = 6 as int32;

// ---- Types ----------------------------------------------------------------

export interface WindowOptions {
    title: string;
    width: int32;
    height: int32;
    url: string;
    resizable: boolean;
    decorations: boolean;
    alwaysOnTop: boolean;
    transparent: boolean;
    visible: boolean;
    center: boolean;
    fullscreen: boolean;
    x: int32;
    y: int32;
}

export interface Window {
    id: int32;
    label: string;
}

export type WindowEventHandler = (label: string, eventType: int32) => void;

// Build a WindowOptions with sensible defaults — decorated, resizable,
// visible, OS-positioned. Override fields after.
export function defaultOptions(title: string, width: int32, height: int32, url: string): WindowOptions {
    return {
        title, width, height, url,
        resizable: true, decorations: true,
        alwaysOnTop: false, transparent: false,
        visible: true, center: false, fullscreen: false,
        x: 0 as int32, y: 0 as int32,
    };
}

function flagsFromOptions(o: WindowOptions): int32 {
    let f: int32 = 0 as int32;
    if (o.resizable)   f = (f | ION_WIN_RESIZABLE)     as int32;
    if (o.decorations) f = (f | ION_WIN_DECORATIONS)   as int32;
    if (o.alwaysOnTop) f = (f | ION_WIN_ALWAYS_ON_TOP) as int32;
    if (o.transparent) f = (f | ION_WIN_TRANSPARENT)   as int32;
    if (o.visible)     f = (f | ION_WIN_VISIBLE)       as int32;
    if (o.center)      f = (f | ION_WIN_CENTERED)      as int32;
    if (o.fullscreen)  f = (f | ION_WIN_FULLSCREEN)    as int32;
    return f;
}

// ---- Lifecycle ------------------------------------------------------------

export function createWindow(label: string, options: WindowOptions): Window | null {
    if (ionInit() === (0 as int32)) return null as unknown as Window | null;
    const id = ionCreateWindow(label, options.title,
                               options.width, options.height,
                               options.url, flagsFromOptions(options));
    if (id < (0 as int32)) return null as unknown as Window | null;
    if ((options.x !== (0 as int32) || options.y !== (0 as int32)) && !options.center) {
        ionSetWindowPosition(id, options.x, options.y);
    }
    return { id, label } as Window | null;
}

export function closeWindow(win: Window): void {
    ionCloseWindow(win.id);
}

export function getWindow(label: string): Window | null {
    const id = ionFindWindow(label);
    if (id < (0 as int32)) return null as unknown as Window | null;
    return { id, label } as Window | null;
}

export function windowCount(): int32 {
    return ionWindowCount() as int32;
}

// ---- Properties -----------------------------------------------------------

export function show(win: Window):               void { ionShowWindow(win.id); }
export function hide(win: Window):               void { ionHideWindow(win.id); }
export function focus(win: Window):              void { ionFocusWindow(win.id); }
export function minimize(win: Window):           void { ionMinimizeWindow(win.id); }
export function maximize(win: Window):           void { ionMaximizeWindow(win.id); }

export function setTitle(win: Window, title: string):                void { ionSetWindowTitle(win.id, title); }
export function setSize(win: Window, width: int32, height: int32):   void { ionSetWindowSize(win.id, width, height); }
export function pixelWidth(win: Window):  int32 { return ionWindowPixelWidth(win.id); }
export function pixelHeight(win: Window): int32 { return ionWindowPixelHeight(win.id); }
export function setPosition(win: Window, x: int32, y: int32):        void { ionSetWindowPosition(win.id, x, y); }
export function setAlwaysOnTop(win: Window, on: boolean):            void { ionSetWindowAlwaysOnTop(win.id, on ? (1 as int32) : (0 as int32)); }
export function setDecorations(win: Window, on: boolean):            void { ionSetWindowDecorations(win.id, on ? (1 as int32) : (0 as int32)); }
export function setWindowContentProtected(win: Window, on: boolean): void { ionSetWindowContentProtected(win.id, on ? (1 as int32) : (0 as int32)); }

// Per-window file picker. Returns "" on cancel.
export function fileOpen(win: Window): string {
    return ionFileOpenWindow(win.id);
}

// ---- IPC (MS → JS) --------------------------------------------------------

// Build the JS dispatch string the same way ipc.ms#invoke does, so MS-emitted
// events reach the same `_dispatch(name, payload)` slot that bootstrap.c
// installs on `window.__ion__`. The npm package's on(name, handler) routes
// from there.
function buildDispatchJS(event: string, payload: string): string {
    const safeName = jsEscape(event);
    const safePayload = jsEscape(payload);
    return `if(window.__ion__&&window.__ion__._dispatch)window.__ion__._dispatch("${safeName}","${safePayload}")`;
}

// Send an event to a specific window by label. Silently no-op if no window
// has that label.
export function emitTo(label: string, event: string, payload: string): void {
    const id = ionFindWindow(label);
    if (id < (0 as int32)) return;
    ionEvalJSWindow(id, buildDispatchJS(event, payload));
}

// Broadcast to every live window. Iteration uses the C registry's order;
// new windows created during dispatch are NOT included in the current call.
export function emitAll(event: string, payload: string): void {
    const js = buildDispatchJS(event, payload);
    // Iterate by id 0..ION_MAX_WINDOWS-1; ionEvalJSWindow is a no-op for
    // inactive slots, so we don't need a separate active-id iterator on
    // the MS side.
    for (let i = 0 as int32; i < (16 as int32); i = (i + 1) as int32) {
        ionEvalJSWindow(i, js);
    }
}

// ---- Window event handler registration ------------------------------------

// Array-push pattern: top-level let with arrow-function init isn't lowered
// by the recompiler (becomes "unlowered ArrowFunction" → undefined module
// init symbol). Empty array + for-of dispatch is the Bug-5-safe shape that
// command.ms / ipc.ms already use.
const _windowEventHandlers: WindowEventHandler[] = [];

// Register a window-event handler. Multiple registrations are allowed —
// every handler fires for every event.
export function onWindowEvent(handler: WindowEventHandler): void {
    _windowEventHandlers.push(handler);
}

// Called by ipc.ms runLoop when ionPollEvent returns 3. Internal.
export function dispatchWindowEvent(label: string, eventType: int32): void {
    for (const h of _windowEventHandlers) h(label, eventType);
}

// Called by ipc.ms runLoop when an IPC message arrives on the reserved
// "__emit" channel. Parses the envelope, then routes via emitTo (specific
// target) or emitAll (broadcast when target is empty). Internal.
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
