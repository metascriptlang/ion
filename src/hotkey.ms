// Global (system-wide) hotkeys.
//
// macOS:   Carbon RegisterEventHotKey — exclusive, system-wide, no Accessibility
//          permission required, fires even when app is unfocused.
// Windows: RegisterHotKey (Phase 4 — Phase 1 stub returns -1).
//
// Hit → IPC message "hotkey" delivered to listen() handlers with
// payload = id (as string).
//
// Public API (`registerHotkeyKey`, `tryRegisterHotkeyKey`) takes a portable
// key NAME like "L"; the right native keycode (Carbon vk on macOS, Win32
// VK_* on Windows) is selected at runtime via `keyCodeFromName()`.

import {
	ionRegisterHotkey, ionUnregisterHotkey,
} from "./platform/bridge.h";
import { platform } from "std/process";

// Outcomes from registration. Use `tryRegisterHotkey*` to get a typed
// outcome; `registerHotkey*` collapses to boolean for the common case
// where caller doesn't care which failure mode hit.
export enum HotkeyResult {
	Ok          = 0,
	UnknownKey  = 1,  // key name not in keyCodeFromName table
	SlotsFull   = 2,  // too many active hotkeys (16 max)
	Conflict    = 3,  // Carbon refused — combo taken by OS or another app
}

// Low-level: pass the platform-native virtual key code directly:
//   macOS:   Carbon kVK_ANSI_* (e.g. 37 for 'L')
//   Windows: Win32 VK_* (e.g. 0x4C for 'L')
// Prefer `registerHotkeyKey(mods, "L", id)` — it picks the right code for you.
// modifiers = ModCmd | ModShift | ... (from "@metascript/ion/mods").
export function registerHotkey(modifiers: int32, keyCode: int32, id: int32): boolean {
	return ionRegisterHotkey(modifiers, keyCode, id) === 1;
}

// Same with structured outcome.
export function tryRegisterHotkey(modifiers: int32, keyCode: int32, id: int32): HotkeyResult {
	const r = ionRegisterHotkey(modifiers, keyCode, id);
	if (r === 1)  return HotkeyResult.Ok;
	if (r === 0)  return HotkeyResult.SlotsFull;
	return HotkeyResult.Conflict;  // -1 from bridge
}

// Convenience: pass a key name. Supported (case-insensitive):
//   "A".."Z", "0".."9", "F1".."F12",
//   "Space", "Return"/"Enter", "Tab", "Escape"/"Esc",
//   "Delete"/"Backspace", "Up", "Down", "Left", "Right".
//
// Returns false if name is unknown OR registration fails (combo already
// taken by the OS or another app).
export function registerHotkeyKey(modifiers: int32, key: string, id: int32): boolean {
	const code = keyCodeFromName(key);
	if (code < 0) return false;
	return ionRegisterHotkey(modifiers, code, id) === 1;
}

// Same with structured outcome — distinguish unknown-key from collision.
export function tryRegisterHotkeyKey(modifiers: int32, key: string, id: int32): HotkeyResult {
	const code = keyCodeFromName(key);
	if (code < 0) return HotkeyResult.UnknownKey;
	return tryRegisterHotkey(modifiers, code, id);
}

export function unregisterHotkey(id: int32): void {
	ionUnregisterHotkey(id);
}

// Resolve a portable key name to the build target's native virtual key code.
// Dispatches by runtime `platform` so the same MS source compiles correctly
// for either OS. Returns -1 if the name is unknown OR the platform is not
// supported. Names are case-insensitive.
//
// Supported names (case-insensitive):
//   "A".."Z", "0".."9", "F1".."F12",
//   "Space", "Return"/"Enter", "Tab", "Escape"/"Esc",
//   "Delete"/"Backspace", "Up", "Down", "Left", "Right".
//
// Note: "Delete"/"Backspace" both map to the same physical key (Mac's
// "delete" key sits in the PC "Backspace" position; on Windows we map both
// to VK_BACK). Apps wanting Windows' forward-delete key should use the raw
// `registerHotkey(mods, 0x2E, id)` form.
export function keyCodeFromName(name: string): int32 {
	if (name.length === 0) return -1 as int32;
	const k = name.toUpperCase();
	if (platform === "darwin")  return keyCodeFromNameMacOS(k);
	if (platform === "windows") return keyCodeFromNameWindows(k);
	if (platform === "linux")   return keyCodeFromNameLinux(k);
	return -1 as int32;
}

// ---- macOS Carbon virtual key codes (kVK_ANSI_* + special keys) -----------

function keyCodeFromNameMacOS(k: string): int32 {
	if (k === "A") return 0 as int32;
	if (k === "S") return 1 as int32;
	if (k === "D") return 2 as int32;
	if (k === "F") return 3 as int32;
	if (k === "H") return 4 as int32;
	if (k === "G") return 5 as int32;
	if (k === "Z") return 6 as int32;
	if (k === "X") return 7 as int32;
	if (k === "C") return 8 as int32;
	if (k === "V") return 9 as int32;
	if (k === "B") return 11 as int32;
	if (k === "Q") return 12 as int32;
	if (k === "W") return 13 as int32;
	if (k === "E") return 14 as int32;
	if (k === "R") return 15 as int32;
	if (k === "Y") return 16 as int32;
	if (k === "T") return 17 as int32;
	if (k === "1") return 18 as int32;
	if (k === "2") return 19 as int32;
	if (k === "3") return 20 as int32;
	if (k === "4") return 21 as int32;
	if (k === "6") return 22 as int32;
	if (k === "5") return 23 as int32;
	if (k === "9") return 25 as int32;
	if (k === "7") return 26 as int32;
	if (k === "8") return 28 as int32;
	if (k === "0") return 29 as int32;
	if (k === "O") return 31 as int32;
	if (k === "U") return 32 as int32;
	if (k === "I") return 34 as int32;
	if (k === "P") return 35 as int32;
	if (k === "L") return 37 as int32;
	if (k === "J") return 38 as int32;
	if (k === "K") return 40 as int32;
	if (k === "N") return 45 as int32;
	if (k === "M") return 46 as int32;
	if (k === "RETURN" || k === "ENTER")     return 36 as int32;
	if (k === "TAB")                          return 48 as int32;
	if (k === "SPACE")                        return 49 as int32;
	if (k === "DELETE" || k === "BACKSPACE") return 51 as int32;
	if (k === "ESCAPE" || k === "ESC")       return 53 as int32;
	if (k === "F1")  return 122 as int32;
	if (k === "F2")  return 120 as int32;
	if (k === "F3")  return 99  as int32;
	if (k === "F4")  return 118 as int32;
	if (k === "F5")  return 96  as int32;
	if (k === "F6")  return 97  as int32;
	if (k === "F7")  return 98  as int32;
	if (k === "F8")  return 100 as int32;
	if (k === "F9")  return 101 as int32;
	if (k === "F10") return 109 as int32;
	if (k === "F11") return 103 as int32;
	if (k === "F12") return 111 as int32;
	if (k === "UP")    return 126 as int32;
	if (k === "DOWN")  return 125 as int32;
	if (k === "LEFT")  return 123 as int32;
	if (k === "RIGHT") return 124 as int32;
	return -1 as int32;
}

// ---- Win32 virtual key codes (VK_* from winuser.h) ------------------------
//
// Letters and digits are ASCII-aligned: VK_A = 0x41, VK_0 = 0x30, etc.
// (Inlined here rather than depending on a winuser.h import — these constants
// haven't changed since Windows 3.0 and won't.)

function keyCodeFromNameWindows(k: string): int32 {
	// A-Z → 0x41-0x5A
	if (k.length === 1) {
		const c = k.charCodeAt(0);
		if (c >= 65 && c <= 90) return c as int32;          // 'A'..'Z'
		if (c >= 48 && c <= 57) return c as int32;          // '0'..'9' (VK_0..VK_9)
	}
	if (k === "RETURN" || k === "ENTER")     return 0x0D as int32;  // VK_RETURN
	if (k === "TAB")                          return 0x09 as int32;  // VK_TAB
	if (k === "SPACE")                        return 0x20 as int32;  // VK_SPACE
	if (k === "DELETE" || k === "BACKSPACE") return 0x08 as int32;  // VK_BACK
	if (k === "ESCAPE" || k === "ESC")       return 0x1B as int32;  // VK_ESCAPE
	if (k === "F1")  return 0x70 as int32;
	if (k === "F2")  return 0x71 as int32;
	if (k === "F3")  return 0x72 as int32;
	if (k === "F4")  return 0x73 as int32;
	if (k === "F5")  return 0x74 as int32;
	if (k === "F6")  return 0x75 as int32;
	if (k === "F7")  return 0x76 as int32;
	if (k === "F8")  return 0x77 as int32;
	if (k === "F9")  return 0x78 as int32;
	if (k === "F10") return 0x79 as int32;
	if (k === "F11") return 0x7A as int32;
	if (k === "F12") return 0x7B as int32;
	if (k === "UP")    return 0x26 as int32;  // VK_UP
	if (k === "DOWN")  return 0x28 as int32;  // VK_DOWN
	if (k === "LEFT")  return 0x25 as int32;  // VK_LEFT
	if (k === "RIGHT") return 0x27 as int32;  // VK_RIGHT
	return -1 as int32;
}

// ---- Linux X11 KeySyms (XK_* from X11/keysymdef.h) ------------------------
//
// XGrabKey expects display-specific keycodes; the native bridge converts
// KeySym → KeyCode via XKeysymToKeycode at registration time. Letters use
// the lowercase form (Shift is part of the modifier mask, not the keysym).

function keyCodeFromNameLinux(k: string): int32 {
	// Letters + digits: ASCII-aligned. KeySyms use lowercase for letters
	// (Shift lives in the modifier mask, not in the keysym).
	if (k.length === 1) {
		const c = k.charCodeAt(0);
		if (c >= 65 && c <= 90) return (c + 32) as int32;   // 'A'..'Z' → 0x61..0x7A
		if (c >= 48 && c <= 57) return c as int32;          // '0'..'9' → 0x30..0x39
	}
	return match (k) {
		"RETURN" | "ENTER"     => 0xFF0D as int32,
		"TAB"                   => 0xFF09 as int32,
		"SPACE"                 => 0x0020 as int32,
		"DELETE" | "BACKSPACE" => 0xFF08 as int32,
		"ESCAPE" | "ESC"       => 0xFF1B as int32,
		"F1"  => 0xFFBE as int32,
		"F2"  => 0xFFBF as int32,
		"F3"  => 0xFFC0 as int32,
		"F4"  => 0xFFC1 as int32,
		"F5"  => 0xFFC2 as int32,
		"F6"  => 0xFFC3 as int32,
		"F7"  => 0xFFC4 as int32,
		"F8"  => 0xFFC5 as int32,
		"F9"  => 0xFFC6 as int32,
		"F10" => 0xFFC7 as int32,
		"F11" => 0xFFC8 as int32,
		"F12" => 0xFFC9 as int32,
		"UP"    => 0xFF52 as int32,
		"DOWN"  => 0xFF54 as int32,
		"LEFT"  => 0xFF51 as int32,
		"RIGHT" => 0xFF53 as int32,
		_ => -1 as int32,
	};
}
