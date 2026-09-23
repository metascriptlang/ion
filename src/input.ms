// Keyboard, text, IME, focus and resize events for render surfaces — the
// ionPollEvent → 4 types above pointer input (bridge.h ionInput*). runLoop
// hands every such event to dispatchInput; pointer types stay on onInput.

import {
	ionInputSurface,
	ionInputP1,
	ionInputP2,
	ionInputX,
	ionInputKey,
	ionInputScancode,
	ionInputMods,
	ionInputConsumedMods,
	ionInputUnshifted,
	ionInputText,
	ionKeyName,
} from "./platform/bridge.h";

export const InputKey: int32 = 4 as int32;
export const InputText: int32 = 5 as int32;
export const InputPreedit: int32 = 6 as int32;
export const InputFocus: int32 = 7 as int32;
export const InputResize: int32 = 8 as int32;

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
	surface: int32;
	action: KeyAction;
	key: int32;
	scancode: int32;
	mods: BitSet<KeyMod>;
	consumedMods: BitSet<KeyMod>;
	unshifted: int32;
	text: string;
}

export type KeyHandler = (e: KeyEvent) => void;
export type TextHandler = (surface: int32, text: string) => void;
export type PreeditHandler = (surface: int32, text: string, cursor: int32) => void;
export type SurfaceFocusHandler = (surface: int32, focused: boolean) => void;
export type SurfaceResizeHandler = (surface: int32, width: int32, height: int32, scale: float64) => void;

const _keyHandlers: KeyHandler[] = [];
const _textHandlers: TextHandler[] = [];
const _preeditHandlers: PreeditHandler[] = [];
const _focusHandlers: SurfaceFocusHandler[] = [];
const _resizeHandlers: SurfaceResizeHandler[] = [];

export function onKey(fn: KeyHandler): void { _keyHandlers.push(fn); }
export function onText(fn: TextHandler): void { _textHandlers.push(fn); }
export function onImePreedit(fn: PreeditHandler): void { _preeditHandlers.push(fn); }
export function onSurfaceFocus(fn: SurfaceFocusHandler): void { _focusHandlers.push(fn); }
export function onSurfaceResize(fn: SurfaceResizeHandler): void { _resizeHandlers.push(fn); }

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

function dispatchKey(surface: int32): void {
	const e: KeyEvent = {
		surface: surface,
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

function dispatchText(surface: int32): void {
	const text = ionInputText();
	for (const h of _textHandlers) h(surface, text);
}

function dispatchPreedit(surface: int32): void {
	const text = ionInputText();
	const cursor = ionInputP1() as int32;
	for (const h of _preeditHandlers) h(surface, text, cursor);
}

function dispatchFocus(surface: int32): void {
	const focused = ionInputP1() !== 0.0;
	for (const h of _focusHandlers) h(surface, focused);
}

function dispatchResize(surface: int32): void {
	const width = ionInputP1() as int32;
	const height = ionInputP2() as int32;
	const scale = ionInputX();
	for (const h of _resizeHandlers) h(surface, width, height, scale);
}

export function dispatchInput(type: int32): void {
	const surface = ionInputSurface() as int32;
	match (type) {
		4 => dispatchKey(surface),
		5 => dispatchText(surface),
		6 => dispatchPreedit(surface),
		7 => dispatchFocus(surface),
		8 => dispatchResize(surface),
		_ => {},
	};
}
