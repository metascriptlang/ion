// Low-level IPC: JS↔MS message channel + the blocking event loop.
//
// Two roles in one file because runLoop polls events and dispatches IPC
// messages to listeners — they share the handlers state. Higher-level
// `command()` (Tauri-style Promise) is built on top in command.ms.
//
// This file also owns the platform build directives (compile bridge.m
// + link flags) — it's the canonical bridge consumer, so the directives
// always make it into the build graph regardless of which sub-module
// the app imports.
//
// Handler shape: receives (name, payload). Listener routes on `name`.
//
// v0 stores handlers in a flat array because Map<string, FunctionType>
// hits MS Bug 5 — see docs/COMPILER-BUGS.md. Linear iteration via for-of
// works correctly.

// Each platform's source files get their own @compile. MS recompiler
// dedupes by path via _compiledOFiles, so listing the same file twice is
// safe. We list them all here to keep the build manifest centralized.
//
// common/*.c is plain C, shared across all platforms — always compiled.
// macOS-specific .m files and Windows-specific .c files live behind
// @platform("...") blocks so cross-compile only pulls the right set.
// Recompiler's @platform filter (src/checker/checkPass.ms:collectDirectives)
// drops mismatched blocks at directive-collection time.

@compile("./platform/common/randombytes.c");
@compile("./platform/common/invokekey.c");
@compile("./platform/common/queue.c");
@compile("./platform/common/windowRegistry.c");
@compile("./platform/common/windowEvents.c");
@compile("./platform/common/inputEvents.c");
@compile("./platform/common/navpolicy.c");
@compile("./platform/common/bootstrap.c");
@compile("./platform/common/json_extract.c");
@compile("./platform/common/mime.c");
@compile("./platform/common/protoReg.c");

when (macos) {
	@compile("./platform/macos/state.m", "-fobjc-arc");
	@compile("./platform/macos/core/lifecycle.m", "-fobjc-arc");
	@compile("./platform/macos/core/window.m", "-fobjc-arc");
	@compile("./platform/macos/core/renderSurface.m", "-fobjc-arc");
	@compile("./platform/macos/core/shell.m", "-fobjc-arc");
	@compile("./platform/macos/webview/bootstrap.m", "-fobjc-arc");
	@compile("./platform/macos/webview/nav_delegate.m", "-fobjc-arc");
	@compile("./platform/macos/webview/eval.m", "-fobjc-arc");
	@compile("./platform/macos/webview/poll.m", "-fobjc-arc");
	@compile("./platform/macos/webview/protocol.m", "-fobjc-arc");
	@compile("./platform/macos/ipc/url_scheme.m", "-fobjc-arc");
	@compile("./platform/macos/chrome/menu.m", "-fobjc-arc");
	@compile("./platform/macos/chrome/tray.m", "-fobjc-arc");
	@compile("./platform/macos/chrome/notify.m", "-fobjc-arc");
	@compile("./platform/macos/chrome/dialog.m", "-fobjc-arc");
	@compile("./platform/macos/input/hotkey.m", "-fobjc-arc");
	@compile("./platform/macos/security/content_protect.m", "-fobjc-arc");
	@compile("./platform/macos/security/keychain.m", "-fobjc-arc");
	@compile("./platform/macos/update/install.m", "-fobjc-arc");
	@passC("-I/opt/homebrew/opt/sdl3/include");
	@passL("-L/opt/homebrew/opt/sdl3/lib");
	@passL("-lSDL3");
	// Reserve rpath so consumers can ship libSDL3.0.dylib bundled in their
	// .app's Contents/Frameworks/. Reserve header padding so make-app.sh can
	// install_name_tool the dev rpath out at packaging time.
	@passL("-Wl,-rpath,@executable_path/../Frameworks");
	@passL("-Wl,-headerpad_max_install_names");
	@passL("-framework Cocoa");
	@passL("-framework WebKit");
	@passL("-framework UserNotifications");
	@passL("-framework Carbon");
	@passL("-framework Security");
}

when (linux) {
	// Phase 2: WebKitGTK webview + bootstrap + IPC + nav + custom URI scheme.
	// Phase 3 wires libayatana-appindicator3 (tray) + libnotify + GtkFileChooser.
	// Phase 4 wires X11 XGrabKey global hotkey. Phase 5 packages as AppImage.
	@compile("./platform/linux/state.c");
	@compile("./platform/linux/core/lifecycle.c");
	@compile("./platform/linux/core/window.c");
	@compile("./platform/linux/core/shell.c");
	@compile("./platform/linux/webview/poll.c");
	@compile("./platform/linux/webview/setup.c");
	@compile("./platform/linux/webview/messaging.c");
	@compile("./platform/linux/webview/nav.c");
	@compile("./platform/linux/webview/eval.c");
	@compile("./platform/linux/webview/protocol.c");
	@compile("./platform/linux/chrome/tray.c");
	@compile("./platform/linux/chrome/notify.c");
	@compile("./platform/linux/chrome/dialog.c");
	@compile("./platform/linux/input/hotkey.c");
	@compile("./platform/linux/security/content_protect.c");
	@compile("./platform/linux/security/keychain.c");
	@compile("./platform/linux/update/install.c");
	// GTK3 + WebKitGTK + libnotify + libayatana-appindicator3 + libsecret
	// include + link flags via pkg-config. Works across x86_64 / aarch64 /
	// Fedora / musl uniformly. libsecret talks to the freedesktop Secret
	// Service (GNOME Keyring / KWallet) for ionKeychainSet/Get/Delete.
	const gtkCflags = @comptime {
		const r = exec("pkg-config --cflags gtk+-3.0 webkit2gtk-4.1 libnotify ayatana-appindicator3-0.1 libsecret-1");
		if (!r.ok) return "";
		return r.value.trim();
	};
	const gtkLibs = @comptime {
		const r = exec("pkg-config --libs gtk+-3.0 webkit2gtk-4.1 libnotify ayatana-appindicator3-0.1 libsecret-1");
		if (!r.ok) return "";
		return r.value.trim();
	};
	@passC(gtkCflags);
	@passL(gtkLibs);
	// XGrabKey + XKeysymToKeycode live in libX11. Pkg-config gtk+-3.0 +
	// webkit2gtk-4.1 link gdk-3 but not X11 directly — ld --as-needed strips
	// the X11 reference unless we name it explicitly here.
	@passL("-lX11");
}

when (windows) {
	// Phase 2: Win32 host window + WebView2 child + IPC plumbing. Phase 3
	// replaces the chrome/* stubs with real Shell_NotifyIcon + Toast WinRT
	// + IFileOpenDialog impls. Phase 4 wires global hotkey via RegisterHotKey.
	@compile("./platform/windows/state.c");
	@compile("./platform/windows/utf8.c");
	@compile("./platform/windows/core/lifecycle.c");
	@compile("./platform/windows/core/window.c");
	@compile("./platform/windows/core/shell.c");
	@compile("./platform/windows/webview/poll.c");
	@compile("./platform/windows/webview/controller.cpp");
	@compile("./platform/windows/webview/messaging.cpp");
	@compile("./platform/windows/webview/nav.cpp");
	@compile("./platform/windows/webview/eval.cpp");
	@compile("./platform/windows/webview/protocol.cpp");
	@compile("./platform/windows/chrome/tray.c");
	@compile("./platform/windows/chrome/notify.c");
	@compile("./platform/windows/chrome/dialog.c");
	@compile("./platform/windows/input/hotkey.c");
	@compile("./platform/windows/security/content_protect.c");
	@compile("./platform/windows/security/keychain.c");
	@compile("./platform/windows/update/install.c");
	// WebView2 SDK headers — vendored under vendor/webview2/include/.
	// Path is resolved relative to the build CWD (ion/ project root).
	@passC("-I./vendor/webview2/include");
	// Win32 link libs — Win32 API + COM + bcrypt (consumed by common/randombytes.c).
	@passL("-luser32");
	@passL("-lgdi32");
	@passL("-lole32");
	@passL("-lshell32");
	@passL("-lshlwapi");  // SHCreateMemStream (used by custom-protocol response builder)
	@passL("-lbcrypt");
	@passL("-luuid");
	@passL("-ladvapi32");  // Credential Manager: CredWriteW / CredReadW / CredDeleteW
	// GUI subsystem — suppresses the default console window that pops up when
	// the user double-clicks a .exe. Without this flag, the linker defaults to
	// console subsystem and a terminal appears next to our window.
	//
	// Trade-off: console subsystem keeps stdout/stderr attached; GUI subsystem
	// detaches them. `console.log` from MS code becomes a no-op for the user.
	// Debug builds can redirect (`app.exe > log.txt 2>&1`) — see scripts/run.bat
	// pattern. A later phase can wire AllocConsole() behind an env var.
	@passL("-Wl,--subsystem,windows");
}

import {
	ionPollEvent,
	ionMessageName, ionMessagePayload,
	ionWindowEventId, ionWindowEventType, ionWindowLabel,
	ionInputType, ionInputX, ionInputY, ionInputP1, ionInputP2,
	ionEvalJS,
	ionClose, ionQuit,
} from "./platform/bridge.h";
import { jsEscape } from "./internal/jsEscape";
import { dispatchWindowEvent, routeEmit } from "./windowManager";

export type Handler = (name: string, payload: string) => void;

const handlers: Handler[] = [];

// Register a JS→MS message handler. JS calls invoke()/call() from the
// @metascriptlang/ion npm package; every registered handler here receives
// (name, payload) and routes itself.
export function listen(handler: Handler): void {
	handlers.push(handler);
}

// Per-frame callbacks — invoked once per runLoop poll iteration. A render-
// surface consumer drives its native renderer here (e.g. godotIteration()),
// keeping the engine tick on the loop thread. Same empty-array + for-of shape
// as `handlers` (Bug-5-safe; see windowManager). Native vsync-accurate ticking
// (CVDisplayLink) is a later phase — see docs/RENDER-SURFACE.md.
const _frameCallbacks: (() => void)[] = [];

export function onFrame(fn: () => void): void {
	_frameCallbacks.push(fn);
}

// Input event callbacks — invoked when ionPollEvent surfaces a mouse event
// (ionPollEvent returns 4). A render-surface consumer forwards these into its
// native renderer's input. type: 1=button, 2=motion, 3=wheel; (x,y) a fraction
// (0..1) of the surface; (p1,p2) carry button/pressed, relX/relY, or wheel dx/dy per type (see
// bridge.h ionInput*). Same empty-array + for-of shape as the other hooks.
export type InputHandler = (type: int32, x: float64, y: float64, p1: float64, p2: float64) => void;

const _inputCallbacks: InputHandler[] = [];

export function onInput(fn: InputHandler): void {
	_inputCallbacks.push(fn);
}

// Send a MS→JS message. JS-side handlers registered via on(name, h) from
// @metascriptlang/ion receive the payload string.
export function invoke(name: string, payload: string): void {
	const safeName = jsEscape(name);
	const safePayload = jsEscape(payload);
	const js = `if(window.__ion__&&window.__ion__._dispatch)window.__ion__._dispatch("${safeName}","${safePayload}")`;
	ionEvalJS(js);
}

// Raw JS evaluation, escape hatch when invoke()'s shape doesn't fit.
export function eval(js: string): void {
	ionEvalJS(js);
}

// Reserved channel — JS-side emit/emitTo posts here; MS routes via
// windowManager.routeEmit. Keep in sync with web/src/protocol.ts (CHANNEL_EMIT)
// and src/platform/common/protocol.h (ION_CHANNEL_EMIT).
const CHANNEL_EMIT = "__emit";

// Block on the SDL event loop, dispatching IPC messages to registered
// listeners. Returns when the user closes the window (or Cmd+Q). Tears
// down ion afterwards.
export function runLoop(): void {
	let running = true;
	while (running) {
		const evt = ionPollEvent();
		if (evt === 1) {
			running = false;
		} else if (evt === 2) {
			const name = ionMessageName();
			const payload = ionMessagePayload();
			if (name === CHANNEL_EMIT) {
				routeEmit(payload);
			} else {
				for (const h of handlers) h(name, payload);
			}
		} else if (evt === 3) {
			const id    = ionWindowEventId();
			const type  = ionWindowEventType();
			const label = ionWindowLabel(id);
			dispatchWindowEvent(label, type);
		} else if (evt === 4) {
			const it  = ionInputType();
			const ix  = ionInputX();
			const iy  = ionInputY();
			const ip1 = ionInputP1();
			const ip2 = ionInputP2();
			for (const ih of _inputCallbacks) ih(it, ix, iy, ip1, ip2);
		}
		if (running) {
			for (const fc of _frameCallbacks) fc();
		}
	}
	ionClose();
	ionQuit();
}
