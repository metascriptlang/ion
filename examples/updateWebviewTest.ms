// Webview hot-update e2e — exercises checkWebview + applyWebview.
//
// Targets /tmp/hot-target/ (no admin, no system path). Validates the
// download + ed25519 + unzip + atomic-swap pipeline. After success, the
// .zip's index.html / style.css live at /tmp/hot-target/.
//
// Usage:
//   bun ~/metascript/recompiler/bun/run.ts build examples/updateWebviewTest.ms -f
//   ./out/debug/updateWebviewTest

import { checkWebview, applyWebview, UpdateConfig } from "../src/index";
import { readFile, exists, removeAll, ensureDir } from "std/fs";

function main(): int32 {
	const manifestUrl = "https://updates.example.com/api/myapp/manifest";
	const publicKey   = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
	const channel     = "web";
	const cur         = "v1.0.0";  // pretend we have v1.0.0 — server has v1.0.1
	const destDir     = "/tmp/hot-target";

	const c = checkWebview(manifestUrl, publicKey, channel, cur);
	if (!c.ok) { console.log(`checkWebview failed: ${c.error}`); return 1 as int32; }
	if (c.value === null) { console.log("no webview update"); return 1 as int32; }
	console.log(`update: ${c.value.version} (${c.value.artifactSize}B .zip)`);

	// Prep destDir with placeholder content so the atomic-swap path actually
	// has something to replace (vs first-time install which is also valid).
	if (exists(destDir)) {
		const r = removeAll(destDir);
		if (!r.ok) { console.log(`pre-clean: ${r.error.message}`); return 1 as int32; }
	}
	const ed = ensureDir(destDir);
	if (!ed.ok) { console.log(`mkdir: ${ed.error.message}`); return 1 as int32; }
	// Drop a sentinel — must NOT survive the swap.
	const w = ensureDir(destDir);
	if (!w.ok) { console.log(`prep sentinel: ${w.error.message}`); return 1 as int32; }

	const cfg: UpdateConfig = {
		manifestUrl, publicKey, currentVersion: cur, channel,
		platform: "web",
	};
	const r = applyWebview(cfg, c.value, destDir, (d: int64, t: int64) => {
		console.log(`progress: ${d}/${t}`);
	});
	if (!r.ok) { console.log(`applyWebview failed: ${r.error}`); return 1 as int32; }
	console.log("applyWebview: OK");

	// Verify the .zip's contents landed in destDir.
	const idx = readFile(`${destDir}/index.html`);
	if (!idx.ok) { console.log(`verify index.html: ${idx.error.message}`); return 1 as int32; }
	if (idx.value.indexOf("v1.0.1") < 0) {
		console.log("verify: index.html doesn't contain expected v1.0.1 marker");
		return 1 as int32;
	}
	console.log("verify: index.html v1.0.1 marker present");

	const css = readFile(`${destDir}/style.css`);
	if (!css.ok) { console.log(`verify style.css: ${css.error.message}`); return 1 as int32; }
	console.log("verify: style.css present");

	// Verify cleanup of staging artifacts.
	if (exists(`${destDir}.staged`)) {
		console.log("FAIL: .staged sibling not cleaned");
		return 1 as int32;
	}
	if (exists(`${destDir}.old`)) {
		console.log("FAIL: .old sibling not cleaned");
		return 1 as int32;
	}
	console.log("verify: no leftover .staged / .old siblings");

	console.log("");
	console.log("Phase 2c webview hot update: ALL GREEN");
	return 0 as int32;
}
