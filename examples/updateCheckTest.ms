// Smoke test for ion's update.check() Phase 1.
//
// Hits the live ion-ota service at updates.example.com. Server is expected to
// return 404 (no releases yet) — that's a valid "no update" signal that
// check() must surface as Result.ok(null), NOT an error.
//
// Usage:
//   bun ~/metascript/recompiler/bun/run.ts build examples/updateCheckTest.ms -f
//   ./out/debug/updateCheckTest

import { check, UpdateConfig } from "../src/index";

function main(): int32 {
	const cfg: UpdateConfig = {
		manifestUrl:    "https://updates.example.com/api/myapp/manifest",
		// Real MyApp pubkey will be embedded at build time; this stub is
		// fine for check() which doesn't verify signatures (apply() does).
		publicKey:      "PLACEHOLDER",
		currentVersion: "v0.0.1",
		channel:        "stable",
		platform:       "darwin-aarch64",
	};

	const r = check(cfg);
	if (!r.ok) {
		console.log(`check failed: ${r.error}`);
		return 1 as int32;
	}
	if (r.value === null) {
		console.log("no update available (404 or up-to-date)");
		return 0 as int32;
	}
	const u = r.value;
	console.log(`update available: ${u.version}`);
	console.log(`  publishedAt:       ${u.publishedAt}`);
	console.log(`  releaseNotes:      ${u.releaseNotes}`);
	console.log(`  artifactUrl:       ${u.artifactUrl}`);
	console.log(`  artifactSize:      ${u.artifactSize}`);
	console.log(`  artifactHash:      ${u.artifactHash}`);
	console.log(`  artifactSignature: ${u.artifactSignature.slice(0, 24)}...`);
	return 0 as int32;
}
