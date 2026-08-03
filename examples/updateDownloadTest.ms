// Smoke test for ion's update.download() Phase 2a.
//
// Calls check() then download() against the live ion-ota service.
// Verifies the full pipeline: fetch artifact, sha256, ed25519 sig, stage
// to /tmp/ion-update-<ver>/. Exits non-zero on any failure.
//
// Usage:
//   bun ~/metascript/recompiler/bun/run.ts build examples/updateDownloadTest.ms -f
//   ./out/debug/updateDownloadTest

import { check, download, UpdateConfig } from "../src/index";

function main(): int32 {
	const cfg: UpdateConfig = {
		manifestUrl:    "https://updates.example.com/api/myapp/manifest",
		// MyApp's production pubkey — derived from ~/.myapp/ota-priv.pem
		// via `openssl pkey -pubout -outform DER | tail -c 32 | base64`.
		publicKey:      "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
		currentVersion: "v0.0.1",
		channel:        "stable",
		platform:       "darwin-aarch64",
	};

	const c = check(cfg);
	if (!c.ok)        { console.log(`check failed: ${c.error}`); return 1 as int32; }
	if (c.value === null) { console.log("no update — uploaded a fake release first?"); return 1 as int32; }
	const info = c.value;
	console.log(`update available: ${info.version} (${info.artifactSize} bytes)`);

	const dl = download(cfg, info, (done: int64, total: int64) => {
		console.log(`progress: ${done}/${total}`);
	});
	if (!dl.ok) { console.log(`download failed: ${dl.error}`); return 1 as int32; }
	console.log(`staged: ${dl.value}`);
	return 0 as int32;
}
