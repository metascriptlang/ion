// Ion — single-window webview shell for MetaScript.
//
// Public entry point. Re-exports the runtime surface that apps consume.
// Sub-modules are organized by capability. Build directives (compile
// bridge.m, link SDL3 + Cocoa + WebKit + Carbon + UserNotifications)
// live in ipc.ms — the canonical bridge consumer — so re-export-only
// modules like this one don't drop them.

export { resourcePath, resourceUrl } from "./window";
export { listen, messageWebviewId, runLoop, Handler } from "./ipc";
export {
	createWebview, releaseWebview, getWebview, webviewById, webviewWindowId, webviewNode,
	setWebviewBounds, setWebviewVisible, setWebviewTransparent,
	navigate, evalJs, focusWebview, forwardPointer, emit, emitTo, emitAll,
	Webview, PointerMove, PointerDown, PointerUp, PointerWheel, PointerHWheel, PointerLeave,
} from "./webview";
export {
	onPointer, onKey, onText, onImePreedit, onFocus, onResize, onFrame, keyName, keyMods,
	PointerEvent, PointerKind, KeyEvent, KeyAction, KeyMod,
	PointerHandler, KeyHandler, TextHandler, PreeditHandler, FocusHandler, ResizeHandler, FrameHandler,
} from "./input";
export { onWake, WakeHandler } from "./wake";
export { command, Command } from "./command";
export {
	createWindow, closeWindow, getWindow, windowCount, defaultOptions,
	show, hide, focus, minimize, maximize,
	setTitle, setSize, setPosition, pixelWidth, pixelHeight,
	setAlwaysOnTop, setDecorations, setWindowContentProtected,
	fileOpen, onWindowEvent,
	windowRoot, windowDevice, commit, focusContent, setImeRect, setCursor,
	setFramePolicy, setFrameWhenInactive, requestFrame, FrameOnDemand, FrameContinuous,
	CursorArrow, CursorHand, CursorIbeam, CursorCross, CursorResizeH, CursorResizeV, Window, WindowOptions,
	WindowEventCloseRequested, WindowEventDestroyed,
	WindowEventFocused, WindowEventBlurred,
	WindowEventResized, WindowEventMoved,
} from "./windowManager";
export { openFile } from "./dialog";
export { readClipboardText, writeClipboardText } from "./clipboard";
export { openExternal } from "./shell";
export { setContentProtected } from "./security";
export { setSecret, getSecret, deleteSecret } from "./keychain";
export { registerStaticProtocol, registerAssetScope } from "./protocol";
export { installTray, installTrayImage, uninstallTray } from "./tray";
export { setAppMenu, MenuItem, MenuItemKind, MenuRole, Submenu } from "./menu";
export { notify } from "./notify";
export {
	registerHotkey, registerHotkeyKey,
	tryRegisterHotkey, tryRegisterHotkeyKey, HotkeyResult,
	unregisterHotkey, keyCodeFromName,
} from "./hotkey";
export {
	loadSound, unloadSound, playSound, pauseSound, stopSound, seekSound,
	setSoundVolume, setSoundMuted, setSoundLooping, setSoundRate, soundStatus,
	openAudioOutput, writeAudioOutput, audioOutputUnderruns, closeAudioOutput,
	openAudioInput, readAudioInput, audioInputOverruns, closeAudioInput,
	startRecording, pauseRecording, resumeRecording, stopRecording, closeRecording, recordingStatus,
	SoundStatus, RecordingStatus, PcmStream,
} from "./audio";
export { microphoneAccess, requestMicrophoneAccess, cameraAccess, requestCameraAccess, MediaAccess } from "./permission";
export { ModCmd, ModShift, ModAlt, ModCtrl } from "./mods";
export { check, download, apply, checkWebview, applyWebview, UpdateConfig, UpdateInfo } from "./update";
