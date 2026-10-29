import {
	ionInputWindow,
	ionInputP1,
	ionInputP2,
	ionInputX,
	ionInputY,
	ionInputKey,
	ionInputScancode,
	ionInputMods,
	ionInputConsumedMods,
	ionInputUnshifted,
	ionInputText,
	ionKeyName,
} from "./platform/bridge.h";

export const InputButton: int32 = 1 as int32;
export const InputMotion: int32 = 2 as int32;
export const InputWheel: int32 = 3 as int32;
export const InputKey: int32 = 4 as int32;
export const InputText: int32 = 5 as int32;
export const InputPreedit: int32 = 6 as int32;
export const InputFocus: int32 = 7 as int32;
export const InputResize: int32 = 8 as int32;
export const InputFrame: int32 = 9 as int32;
export const InputLeave: int32 = 10 as int32;

export enum PointerKind {
	Button,
	Motion,
	Wheel,
	Leave,
}

// The unit of dx,dy, as W3C WheelEvent.deltaMode: Pixel for motion and for a precise wheel
// device (a trackpad), Line for wheel notches.
export enum DeltaMode {
	Pixel,
	Line,
}

export struct PointerEvent {
	window: int32;
	kind: PointerKind;
	x: float64;
	y: float64;
	button: int32;
	pressed: boolean;
	dx: float64;
	dy: float64;
	deltaMode: DeltaMode;
	mods: BitSet<KeyMod>;
}

export enum KeyAction {
	Release,
	Press,
	Repeat,
}

// Ordinal order is the ION_MOD_* bit order in bridge.h.
export enum KeyMod {
	Shift,
	Ctrl,
	Alt,
	Super,
	CapsLock,
	NumLock,
	ShiftRight,
	CtrlRight,
	AltRight,
	SuperRight,
}

export struct KeyEvent {
	window: int32;
	action: KeyAction;
	key: int32;
	scancode: int32;
	mods: BitSet<KeyMod>;
	consumedMods: BitSet<KeyMod>;
	unshifted: int32;
	text: string;
}

export type PointerHandler = (e: PointerEvent) => void;
export type KeyHandler = (e: KeyEvent) => void;
export type TextHandler = (window: int32, text: string) => void;
export type PreeditHandler = (window: int32, text: string, cursor: int32) => void;
export type FocusHandler = (window: int32, focused: boolean) => void;
export type ResizeHandler = (window: int32, width: int32, height: int32, scale: float64) => void;
export type FrameHandler = (window: int32, timeMs: float64) => void;

// Each dispatch runs the handlers registered when it starts, as DOM dispatch clones its
// listener list: one registered from inside a handler runs from the next event.
const _pointerHandlers: PointerHandler[] = [];
const _keyHandlers: KeyHandler[] = [];
const _textHandlers: TextHandler[] = [];
const _preeditHandlers: PreeditHandler[] = [];
const _focusHandlers: FocusHandler[] = [];
const _resizeHandlers: ResizeHandler[] = [];
const _frameHandlers: FrameHandler[] = [];

export function onPointer(fn: PointerHandler): void { _pointerHandlers.push(fn); }
export function onKey(fn: KeyHandler): void { _keyHandlers.push(fn); }
export function onText(fn: TextHandler): void { _textHandlers.push(fn); }
// `cursor` is in UTF-16 code units into `text`, the unit of every MetaScript string index.
// An empty `text` ends the composition.
export function onImePreedit(fn: PreeditHandler): void { _preeditHandlers.push(fn); }
export function onFocus(fn: FocusHandler): void { _focusHandlers.push(fn); }
export function onResize(fn: ResizeHandler): void { _resizeHandlers.push(fn); }
export function onFrame(fn: FrameHandler): void { _frameHandlers.push(fn); }

export function keyName(key: int32): string {
	return ionKeyName(key);
}

export function keyMods(mask: int32): BitSet<KeyMod> {
	return (mask as uint16) as BitSet<KeyMod>;
}

function keyAction(p1: int32): KeyAction {
	return match (p1) {
		0 => KeyAction.Release,
		2 => KeyAction.Repeat,
		_ => KeyAction.Press,
	};
}

function dispatchPointer(window: int32, kind: PointerKind): void {
	const isButton = kind === PointerKind.Button;
	const e: PointerEvent = {
		window,
		kind,
		x: ionInputX(),
		y: ionInputY(),
		button: isButton ? ionInputP1() as int32 : 0 as int32,
		pressed: isButton && ionInputP2() !== 0.0,
		dx: isButton ? 0.0 : ionInputP1(),
		dy: isButton ? 0.0 : ionInputP2(),
		deltaMode: kind === PointerKind.Wheel && ionInputKey() === (1 as int32) ? DeltaMode.Line : DeltaMode.Pixel,
		mods: keyMods(ionInputMods() as int32),
	};
	const n = _pointerHandlers.length;
	for (let i = 0; i < n; i++) _pointerHandlers[i](e);
}

function dispatchKey(window: int32): void {
	const e: KeyEvent = {
		window,
		action: keyAction(ionInputP1() as int32),
		key: ionInputKey() as int32,
		scancode: ionInputScancode() as int32,
		mods: keyMods(ionInputMods() as int32),
		consumedMods: keyMods(ionInputConsumedMods() as int32),
		unshifted: ionInputUnshifted() as int32,
		text: ionInputText(),
	};
	const n = _keyHandlers.length;
	for (let i = 0; i < n; i++) _keyHandlers[i](e);
}

function dispatchText(window: int32): void {
	const text = ionInputText();
	const n = _textHandlers.length;
	for (let i = 0; i < n; i++) _textHandlers[i](window, text);
}

function dispatchPreedit(window: int32): void {
	const text = ionInputText();
	const cursor = ionInputP1() as int32;
	const n = _preeditHandlers.length;
	for (let i = 0; i < n; i++) _preeditHandlers[i](window, text, cursor);
}

function dispatchFocus(window: int32): void {
	const focused = ionInputP1() !== 0.0;
	const n = _focusHandlers.length;
	for (let i = 0; i < n; i++) _focusHandlers[i](window, focused);
}

function dispatchResize(window: int32): void {
	const width = ionInputP1() as int32;
	const height = ionInputP2() as int32;
	const scale = ionInputX();
	const n = _resizeHandlers.length;
	for (let i = 0; i < n; i++) _resizeHandlers[i](window, width, height, scale);
}

function dispatchFrame(window: int32): void {
	const timeMs = ionInputX();
	const n = _frameHandlers.length;
	for (let i = 0; i < n; i++) _frameHandlers[i](window, timeMs);
}

export function dispatchInput(type: int32): void {
	const window = ionInputWindow() as int32;
	match (type) {
		1 => dispatchPointer(window, PointerKind.Button),
		2 => dispatchPointer(window, PointerKind.Motion),
		3 => dispatchPointer(window, PointerKind.Wheel),
		4 => dispatchKey(window),
		5 => dispatchText(window),
		6 => dispatchPreedit(window),
		7 => dispatchFocus(window),
		8 => dispatchResize(window),
		9 => dispatchFrame(window),
		10 => dispatchPointer(window, PointerKind.Leave),
		_ => {},
	};
}
