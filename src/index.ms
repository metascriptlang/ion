// Ion — single-window webview shell for MetaScript.
//
// Public entry point. Re-exports the runtime surface that apps consume.
// Sub-modules are organized by capability. Build directives (compile
// bridge.m, link SDL3 + Cocoa + WebKit + Carbon + UserNotifications)
// live in ipc.ms — the canonical bridge consumer — so re-export-only
// modules like this one don't drop them.

export { open, close, resourcePath, resourceUrl } from "./window";
export { listen, invoke, eval, runLoop, onFrame, onInput, Handler, InputHandler } from "./ipc";
export {
	renderSurfaceCreate, renderSurfaceAdopt, renderSurfaceAdoptLayer, renderSurfaceLayer,
	renderSurfaceAttachSwapChain, renderSurfaceSetImeRect, webviewSetFrame, webviewSetVisible,
	renderSurfaceSetVisible, renderSurfaceSyncFrame,
	renderSurfaceSetInputRegion, renderSurfaceSetInputRect, renderSurfaceRelease,
	RenderSurfaceId, RenderSurfaceInvalid,
	SurfaceBelow, SurfaceAbove, InputNone, InputFull, InputRect,
} from "./renderSurface";
export {
	onKey, onText, onImePreedit, onSurfaceFocus, onSurfaceResize, keyName, keyMods,
	KeyEvent, KeyAction, KeyMod, KeyHandler, TextHandler, PreeditHandler,
	SurfaceFocusHandler, SurfaceResizeHandler,
} from "./input";
export { command, Command } from "./command";
export {
	createWindow, closeWindow, getWindow, windowCount, defaultOptions,
	show, hide, focus, minimize, maximize,
	setTitle, setSize, setPosition, pixelWidth, pixelHeight,
	setAlwaysOnTop, setDecorations, setWindowContentProtected,
	fileOpen,
	emitTo, emitAll, onWindowEvent,
	WindowEventCloseRequested, WindowEventDestroyed,
	WindowEventFocused, WindowEventBlurred,
	WindowEventResized, WindowEventMoved,
} from "./windowManager";
export { openFile } from "./dialog";
export { openExternal } from "./shell";
export { setContentProtected } from "./security";
export { setSecret, getSecret, deleteSecret } from "./keychain";
export { registerStaticProtocol, registerAssetScope } from "./protocol";
export { installTray, installTrayImage, uninstallTray } from "./tray";
export { notify } from "./notify";
export {
	registerHotkey, registerHotkeyKey,
	tryRegisterHotkey, tryRegisterHotkeyKey, HotkeyResult,
	unregisterHotkey, keyCodeFromName,
} from "./hotkey";
export { ModCmd, ModShift, ModAlt, ModCtrl } from "./mods";
export { check, download, apply, checkWebview, applyWebview, UpdateConfig, UpdateInfo } from "./update";
