// Windows and their content. A window is an empty native root: the app
// builds its content on the window's compositor (windowRoot / windowDevice)
// and adds webviews from webview.ms.
//
// Usage:
//
//   const main = createWindow("main", defaultOptions("MyApp", 1280 as int32, 800 as int32));
//   if (main === null) return 1;

import {
    ionInit, ionRequestSingleInstance, ionCreateWindow, ionCloseWindow, ionWindowCount, ionFindWindow,
    ionShowWindow, ionHideWindow, ionFocusWindow,
    ionMinimizeWindow, ionMaximizeWindow,
    ionSetWindowTitle, ionSetWindowSize, ionSetWindowPosition,
    ionSetWindowAlwaysOnTop, ionSetWindowDecorations,
    ionSetWindowContentProtected,
    ionWindowPixelWidth, ionWindowPixelHeight,
    ionFileOpenWindow,
    ionWindowDevice, ionWindowRoot, ionWindowCommit,
    ionWindowFocusContent, ionWindowSetImeRect, ionWindowSetCursor,
    ionWindowSetFramePolicy, ionWindowSetFrameWhenInactive, ionWindowRequestFrame,
} from "./platform/bridge.h";

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

export function defaultOptions(title: string, width: int32, height: int32): WindowOptions {
    return {
        title, width, height,
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

let _windowOpened = false;

// Opt-in single instance, before the first window. True: this process holds the
// lock. False: an earlier process holds it, our cold-start URL was forwarded to
// it and its window raised; the app decides whether to exit.
export function requestSingleInstance(): boolean {
    if (_windowOpened) throw new Error("requestSingleInstance must be called before the first createWindow");
    return ionRequestSingleInstance() !== (0 as int32);
}

export function createWindow(label: string, options: WindowOptions): Window | null {
    _windowOpened = true;
    if (ionInit() === (0 as int32)) return null as unknown as Window | null;
    const id = ionCreateWindow(label, options.title,
                               options.width, options.height,
                               flagsFromOptions(options));
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
// Moves the window's outer frame top-left (title bar and border included) to x, y in screen pixels, on every platform.
export function setPosition(win: Window, x: int32, y: int32):        void { ionSetWindowPosition(win.id, x, y); }
export function setAlwaysOnTop(win: Window, on: boolean):            void { ionSetWindowAlwaysOnTop(win.id, on ? (1 as int32) : (0 as int32)); }
export function setDecorations(win: Window, on: boolean):            void { ionSetWindowDecorations(win.id, on ? (1 as int32) : (0 as int32)); }
export function setWindowContentProtected(win: Window, on: boolean): void { ionSetWindowContentProtected(win.id, on ? (1 as int32) : (0 as int32)); }

// Per-window file picker. Returns "" on cancel.
export function fileOpen(win: Window): string {
    return ionFileOpenWindow(win.id);
}

// ---- Content ----------------------------------------------------------------

export const FrameOnDemand: int32 = 0 as int32;
export const FrameContinuous: int32 = 1 as int32;

export const CursorArrow: int32 = 0 as int32;
export const CursorHand: int32 = 1 as int32;
export const CursorIbeam: int32 = 2 as int32;
export const CursorCross: int32 = 3 as int32;
export const CursorResizeH: int32 = 4 as int32;
export const CursorResizeV: int32 = 5 as int32;

export function windowRoot(win: Window): Ptr<void> { return ionWindowRoot(win.id); }
export function windowDevice(win: Window): Ptr<void> { return ionWindowDevice(win.id); }
export function commit(win: Window): void { ionWindowCommit(win.id); }
export function focusContent(win: Window): void { ionWindowFocusContent(win.id); }
export function setImeRect(win: Window, x: int32, y: int32, w: int32, h: int32): void { ionWindowSetImeRect(win.id, x, y, w, h); }
export function setCursor(win: Window, cursor: int32): void { ionWindowSetCursor(win.id, cursor); }
export function setFramePolicy(win: Window, policy: int32): void { ionWindowSetFramePolicy(win.id, policy); }
export function setFrameWhenInactive(win: Window, enabled: boolean): void {
    ionWindowSetFrameWhenInactive(win.id, enabled ? (1 as int32) : (0 as int32));
}
export function requestFrame(win: Window): void { ionWindowRequestFrame(win.id); }

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
