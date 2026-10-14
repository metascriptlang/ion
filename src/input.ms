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

export struct PointerEvent {
	window: int32;
	kind: PointerKind;
	x: float64;
	y: float64;
	button: int32;
	pressed: boolean;
	dx: float64;
	dy: float64;
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
	};
	for (const h of _pointerHandlers) h(e);
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
	for (const h of _keyHandlers) h(e);
}

function dispatchText(window: int32): void {
	const text = ionInputText();
	for (const h of _textHandlers) h(window, text);
}

function dispatchPreedit(window: int32): void {
	const text = ionInputText();
	const cursor = ionInputP1() as int32;
	for (const h of _preeditHandlers) h(window, text, cursor);
}

function dispatchFocus(window: int32): void {
	const focused = ionInputP1() !== 0.0;
	for (const h of _focusHandlers) h(window, focused);
}

function dispatchResize(window: int32): void {
	const width = ionInputP1() as int32;
	const height = ionInputP2() as int32;
	const scale = ionInputX();
	for (const h of _resizeHandlers) h(window, width, height, scale);
}

function dispatchFrame(window: int32): void {
	const timeMs = ionInputX();
	for (const h of _frameHandlers) h(window, timeMs);
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
