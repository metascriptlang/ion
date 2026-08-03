// Sandbox e2e — download + mount + find + (manual) ditto to a non-system
// path, so no admin popup is triggered. Validates everything except the
// AppleScript admin elevation step.
//
// Usage:
//   bun ~/metascript/recompiler/bun/run.ts build examples/updateSandboxTest.ms -f
//   ./out/debug/updateSandboxTest

import { check, download, UpdateConfig } from "../src/index";
import { ionUpdateMountDmg, ionUpdateFindAppInVolume, ionUpdateUnmountDmg } from "../src/platform/bridge.h";
import { exec } from "std/process";
import { exists, removeAll } from "std/fs";

function main(): int32 {
	const cfg: UpdateConfig = {
		manifestUrl:    "https://updates.example.com/api/myapp/manifest",
		publicKey:      "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
		currentVersion: "v0.0.1",
		channel:        "stable",
		platform:       "darwin-aarch64",
	};

	const c = check(cfg);
	if (!c.ok) { console.log(`check failed: ${c.error}`); return 1 as int32; }
	if (c.value === null) { console.log("check: no update available"); return 1 as int32; }
	console.log(`check: ${c.value.version} (${c.value.artifactSize}B)`);

	const dl = download(cfg, c.value, (d: int64, t: int64) => {});
	if (!dl.ok) { console.log(`download: ${dl.error}`); return 1 as int32; }
	console.log(`download: staged at ${dl.value}`);

	const mp = ionUpdateMountDmg(dl.value);
	if (mp === "") { console.log("mount: FAIL"); return 1 as int32; }
	console.log(`mount: ${mp}`);

	const srcApp = ionUpdateFindAppInVolume(mp);
	if (srcApp === "") { console.log("find: FAIL"); ionUpdateUnmountDmg(mp); return 1 as int32; }
	console.log(`find: ${srcApp}`);

	// Sandbox copy — /tmp path, no admin required, exercises ditto mechanics.
	const dest = "/tmp/ion-sandbox-target.app";
	if (exists(dest)) {
		const rm = removeAll(dest);
		if (!rm.ok) { console.log(`pre-clean: ${rm.error.message}`); ionUpdateUnmountDmg(mp); return 1 as int32; }
	}
	const ditto = exec(`/usr/bin/ditto '${srcApp}' '${dest}'`);
	if (!ditto.ok) {
		console.log(`ditto: ${ditto.error.message}`);
		ionUpdateUnmountDmg(mp);
		return 1 as int32;
	}
	console.log(`ditto: ${dest} (no admin needed for /tmp)`);

	const u = ionUpdateUnmountDmg(mp);
	console.log(`unmount: ${u === 0 ? "OK" : `FAIL rc=${u}`}`);

	// Verify the copied .app has the expected structure.
	if (!exists(`${dest}/Contents/Info.plist`)) {
		console.log("verify: Info.plist missing");
		return 1 as int32;
	}
	if (!exists(`${dest}/Contents/MacOS/MyApp`)) {
		console.log("verify: executable missing");
		return 1 as int32;
	}
	console.log("verify: bundle structure OK");
	return 0 as int32;
}
