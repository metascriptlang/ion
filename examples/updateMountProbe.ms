// Probe: hdiutil mount + .app find primitives via ion bridge.
// Skips download/verify (uses a local fixture .dmg).
//
// Usage:
//   bun ~/metascript/recompiler/bun/run.ts build examples/updateMountProbe.ms -f
//   ./out/debug/updateMountProbe

// Direct bridge.h import for the test-only primitives; pulling `../src/index`
// in alongside is required for ion's @compile directives in ipc.ms to fire
// (re-export-only paths drop build directives — see vendor/ion/CLAUDE.md).
import "../src/index";
import { ionUpdateMountDmg, ionUpdateFindAppInVolume, ionUpdateUnmountDmg } from "../src/platform/bridge.h";

function main(): int32 {
	const dmg = "/tmp/myapp-fixture.dmg";
	const mp = ionUpdateMountDmg(dmg);
	if (mp === "") { console.log(`mount failed for ${dmg}`); return 1 as int32; }
	console.log(`mounted at: ${mp}`);

	const app = ionUpdateFindAppInVolume(mp);
	if (app === "") { console.log(`no .app at ${mp}`); ionUpdateUnmountDmg(mp); return 1 as int32; }
	console.log(`found app:  ${app}`);

	const u = ionUpdateUnmountDmg(mp);
	console.log(`unmount rc: ${u}`);
	return 0 as int32;
}
