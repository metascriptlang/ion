// Trigger hot-update swap against the running HotUpdateTest.app.
//
// Usage:
//   bun ~/metascript/recompiler/bun/run.ts build examples/hotSwapTrigger.ms -f
//   ./out/debug/hotSwapTrigger
//
// Expected (B pattern):
//   - Files at .../Contents/Resources/web/ swapped on disk → v1.0.1
//   - The HotUpdateTest.app window STILL shows v1.0.0 (cached in webview memory)
//   - After quit + relaunch, window shows v1.0.1

import { checkWebview, applyWebview, UpdateConfig } from "../src/index";

function main(): int32 {
	const manifestUrl = "https://updates.example.com/api/myapp/manifest";
	const publicKey   = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
	const destDir     = "/Applications/HotUpdateTest.app/Contents/Resources/web";

	const c = checkWebview(manifestUrl, publicKey, "web", "v1.0.0");
	if (!c.ok) { console.log(`checkWebview: ${c.error}`); return 1 as int32; }
	if (c.value === null) { console.log("no webview update"); return 1 as int32; }
	console.log(`update: ${c.value.version} (${c.value.artifactSize}B)`);

	const cfg: UpdateConfig = {
		manifestUrl, publicKey,
		currentVersion: "v1.0.0", channel: "web", platform: "web",
	};
	const r = applyWebview(cfg, c.value, destDir, (d: int64, t: int64) => {
		console.log(`progress: ${d}/${t}`);
	});
	if (!r.ok) { console.log(`applyWebview: ${r.error}`); return 1 as int32; }
	console.log(`swap OK at ${destDir}`);
	console.log("");
	console.log("Pattern (B) expectation:");
	console.log("  - Disk now has v1.0.1 files");
	console.log("  - The running HotUpdateTest.app window STILL shows v1.0.0");
	console.log("  - Quit + relaunch HotUpdateTest.app → window shows v1.0.1");
	return 0 as int32;
}
