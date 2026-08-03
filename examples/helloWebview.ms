// Ion v0 demo — open a window, embed webview, round-trip a ping.
//
// Usage:
//   bun ~/metascript/recompiler/bun/run.ts run examples/helloWebview.ms [url] [title]
//
// Loads the bundled hello.html via `ion://localhost/`. When running as a
// packaged .app, hello.html lives in Contents/Resources/ and ion auto-
// registers the `ion://` scheme → resourcePath() at open() time. When
// running unbundled, we explicitly register `ion://` → ./examples/.

import {
	open, listen, invoke, runLoop, command,
	installTrayImage, notify, registerHotkeyKey,
	setContentProtected, registerStaticProtocol,
	ModCmd, ModShift,
} from "../src/index";
import { argv, cwd } from "std/process";
import { parseJson } from "std/serialize/json/parser";
import { asInt32, getDynamicField } from "std/serialize/json/accessors";

// argv[1] can be either a webview URL override (dev/testing) or a deep link
// URL (from the OS routing a `myapp://...` link to our app). Distinguish
// by scheme: webview schemes go to open(), deep links are dispatched by
// native via the "deeplink" IPC, so we just load the normal app shell.
//
// Note: file:// is intentionally NOT in this allowlist — ion's nav delegate
// blocks file:// because of the opaque-origin trap. Use ion:// for bundled
// assets, asset:// for scoped disk files.
function isWebviewUrl(s: string): boolean {
	if (s.indexOf("://") < 0) return false;
	return s.startsWith("http://") || s.startsWith("https://")
		|| s.startsWith("ion://") || s.startsWith("asset://")
		|| s.startsWith("data:");
}

function main(): int32 {
	// When running unbundled (from source tree), resourcePath() returns "" so
	// open()'s auto-register of `ion://` skips. Explicitly register it here
	// pointing at the examples dir so `ion://localhost/hello.html` resolves.
	// In .app mode this register call is harmless — auto-register already
	// ran from open() (or this call wins since both target the resources dir).
	registerStaticProtocol("ion", `${cwd()}/examples`);

	// Override the bundled URL only if argv[1] is a webview-loadable scheme
	// (http/https/ion/asset/data). A custom-scheme URL like `myapp://...`
	// was passed by the OS URL handler — let native route it as "deeplink",
	// and load the regular app shell.
	let url = "ion://localhost/hello.html";
	if (argv.length > 1 && isWebviewUrl(argv[1])) url = argv[1];
	const title = argv.length > 2 ? argv[2] : "Ion v0";

	if (!open(title, 1280 as int32, 800 as int32, url)) {
		console.log("ion: failed to open window");
		return 1;
	}

	listen((name, payload) => {
		if (name === "ping") {
			console.log(`MS ← ping: ${payload}`);
			invoke("pong", `echoing: ${payload}`);
			// Demo notification on each ping.
			notify("Ping received", `payload: ${payload}`, "demo-ping");
		} else if (name === "deeplink") {
			console.log(`MS ← deeplink: ${payload}`);
			notify("Deep link received", payload, "demo-deeplink");
			invoke("deeplink", payload);
		} else if (name === "tray.click") {
			console.log("MS ← tray clicked");
			invoke("trayClick", "ok");
		} else if (name === "notification.click") {
			console.log(`MS ← notification clicked: ${payload}`);
		} else if (name === "hotkey") {
			console.log(`MS ← hotkey id=${payload}`);
			invoke("hotkey", payload);
		} else if (name === "protect") {
			const on = payload === "on" || payload === "1" || payload === "true";
			console.log(`MS ← setContentProtected(${on})`);
			setContentProtected(on);
		} else if (name === "console.log" || name === "console.warn"
		        || name === "console.error" || name === "console.info") {
			console.log(`[webview ${name.replaceAll("console.", "")}] ${payload}`);
		}
	});

	// Tauri-style command: JS calls `await window.ion.call("addNumbers", {a, b})`,
	// gets the sum back as a Promise.
	command("addNumbers", (argsJson) => {
		const parsed = parseJson(argsJson);
		if (!parsed.ok) return "0";
		const args = parsed.value;
		const a = asInt32(getDynamicField(args, "a"));
		const b = asInt32(getDynamicField(args, "b"));
		console.log(`MS command addNumbers(${a}, ${b})`);
		return `${a + b}`;
	});

	// Tray icon — template PNG, auto-adapts to dark/light menu bar.
	// ion tries the path as-is first, then looks up by filename in the .app's
	// Resources/, so this works whether running unbundled or as a bundled .app.
	installTrayImage("tray-icon.png");

	// Cmd+Shift+L → summon.
	registerHotkeyKey(ModCmd | ModShift, "L", 1 as int32);

	// Auto-fire one notification on launch to verify the API.
	notify("Ion ready", "Tray + hotkey + notify wired", "demo-launch");

	runLoop();
	return 0;
}
