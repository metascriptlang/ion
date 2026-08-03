// Full OTA apply() e2e — exercises the complete pipeline:
//   check → download → mount → find → replace (admin) → unmount →
//   relaunchAndExit (helper waits for pid, opens new .app, _exit(0))
//
// Target /Applications/IonUpdateTestStub.app. After the admin popup,
// this process EXITS — anh should see the installed app launch on its
// own (a stub ion window with the helloWebview demo content) while
// this terminal returns to the prompt.
//
// Usage (anh trigger admin popup + watch desktop):
//   ./out/debug/updateFullTest

import { check, apply, UpdateConfig } from "../src/index";

function main(): int32 {
	const cfg: UpdateConfig = {
		manifestUrl:    "https://updates.example.com/api/myapp/manifest",
		publicKey:      "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
		currentVersion: "v0.0.1",
		channel:        "stable",
		platform:       "darwin-aarch64",
	};
	const destAppPath = "/Applications/IonUpdateTestStub.app";

	const c = check(cfg);
	if (!c.ok) { console.log(`check failed: ${c.error}`); return 1 as int32; }
	if (c.value === null) { console.log("no update"); return 1 as int32; }
	console.log(`update: ${c.value.version} (${c.value.artifactSize}B)`);
	console.log("");
	console.log("==> Admin popup will appear next.");
	console.log("==> After install, this process exits and the new app launches.");
	console.log("");

	const r = apply(cfg, c.value, destAppPath, (d: int64, t: int64) => {});

	// Reached only if apply() did NOT relaunch (user cancelled, or failure).
	if (!r.ok) {
		console.log(`apply result: ${r.error}`);
		return r.error.indexOf("cancelled") >= 0 ? 0 as int32 : 1 as int32;
	}
	// Unreachable — successful apply() never returns (relaunchAndExit exits).
	console.log("apply succeeded but did not exit (unexpected)");
	return 1 as int32;
}
