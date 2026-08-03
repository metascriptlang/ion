// Admin-path e2e — exercises ionUpdateReplaceApp's AppleScript "with
// administrator privileges" code path. Target is /tmp/ion-installtest.app
// (safe sandbox — non-system, em owns) so a wrong path here can't damage
// /Applications. relaunchAndExit is intentionally NOT called: the stub
// .app inside the fixture .dmg only has a placeholder executable, so
// relaunching it would fail; that primitive is tested separately against
// a real .app.
//
// Usage (anh trigger admin popup):
//   ./out/debug/updateAdminTest

import { check, download, UpdateConfig } from "../src/index";
import { ionUpdateMountDmg, ionUpdateFindAppInVolume,
         ionUpdateReplaceApp, ionUpdateUnmountDmg } from "../src/platform/bridge.h";
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
	if (c.value === null) { console.log("no update"); return 1 as int32; }
	console.log(`update: ${c.value.version} (${c.value.artifactSize}B)`);

	const dl = download(cfg, c.value, (d: int64, t: int64) => {});
	if (!dl.ok) { console.log(`download: ${dl.error}`); return 1 as int32; }

	const mp = ionUpdateMountDmg(dl.value);
	if (mp === "") { console.log("mount: FAIL"); return 1 as int32; }
	const srcApp = ionUpdateFindAppInVolume(mp);
	if (srcApp === "") { console.log("find: FAIL"); ionUpdateUnmountDmg(mp); return 1 as int32; }
	console.log(`src: ${srcApp}`);

	const dest = "/tmp/ion-installtest.app";
	if (exists(dest)) {
		const rm = removeAll(dest);
		if (!rm.ok) { console.log(`pre-clean: ${rm.error.message}`); ionUpdateUnmountDmg(mp); return 1 as int32; }
	}

	console.log("");
	console.log("==> Admin popup will appear next. This tests the AppleScript");
	console.log("==> 'with administrator privileges' code path. Enter your");
	console.log("==> password or Cancel — both outcomes are verified.");
	console.log("");

	const rc = ionUpdateReplaceApp(srcApp, dest);
	ionUpdateUnmountDmg(mp);

	if (rc === -3) {
		console.log("result: CANCELLED — user clicked Cancel on auth dialog");
		console.log("        (-3 maps to a recoverable error per spec)");
		return 0 as int32;
	}
	if (rc !== 0) {
		console.log(`result: FAIL rc=${rc}`);
		return 1 as int32;
	}

	console.log(`result: OK — installed at ${dest}`);
	if (!exists(`${dest}/Contents/Info.plist`)) {
		console.log("verify: Info.plist missing"); return 1 as int32;
	}
	if (!exists(`${dest}/Contents/MacOS/MyApp`)) {
		console.log("verify: executable missing"); return 1 as int32;
	}
	console.log("verify: bundle structure OK");
	return 0 as int32;
}
