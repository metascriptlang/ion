// Minimal end-to-end demo of ion's custom URI scheme handler.
//
// Registers `demo://` → ./examples/demoAssets/, opens a window at
// `demo://localhost/index.html`, and round-trips a "demo.ready" ping back
// to MS as proof that the IPC bootstrap script reached the page (i.e.
// WKURLSchemeHandler served the HTML AND ion's bootstrap user-script ran
// on the served page, injecting window.__ion__).
//
// Run (raw binary — no bundling needed since we don't touch notify/tray):
//   cd ~/metascript/recompiler
//   bun bun/run.ts build examples/protocolDemo.ms -f
//   out/debug/protocolDemo
//
// Expected: webview shows the demo page with origin "demo://localhost",
// pushState buttons update the URL bar without reload, localStorage
// counter persists across reload. Stdout shows "MS ← demo.ready: demo://localhost".

import {
	open, listen, runLoop,
	registerStaticProtocol,
} from "../src/index";
import { cwd } from "std/process";

function main(): int32 {
	// Absolute baseDir — examples/demoAssets/ relative to wherever we ran from.
	// In .app packaging this would use resourcePath() instead; raw-binary mode
	// uses cwd-relative paths.
	const baseDir = `${cwd()}/vendor/ion/examples/demoAssets`;

	if (!registerStaticProtocol("demo", baseDir)) {
		console.log(`ion: failed to register demo:// (baseDir=${baseDir})`);
		return 1;
	}

	if (!open("ion custom-protocol demo", 900 as int32, 700 as int32,
	          "demo://localhost/index.html")) {
		console.log("ion: failed to open window");
		return 1;
	}

	listen((name, payload) => {
		if (name === "demo.ready") {
			console.log(`MS ← demo.ready: ${payload}`);
		} else if (name === "console.log" || name === "console.warn"
		        || name === "console.error" || name === "console.info") {
			console.log(`[webview ${name.replaceAll("console.", "")}] ${payload}`);
		}
	});

	runLoop();
	return 0;
}
