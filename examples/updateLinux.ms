// Self-update of a running AppImage: version 1 installs the AppImage named by
// ION_UPDATE_FROM over itself and relaunches; version 2 prints and exits.
//
// Usage (Linux host, appimagetool on PATH):
//   msc build examples/updateLinux.ms
//   echo 1 > out/v1/version.txt; echo 2 > out/v2/version.txt
//   ion app out/debug/updateLinux Upd1 dev.ion.Upd --target linux --out out/v1 --asset out/v1/version.txt
//   ion app out/debug/updateLinux Upd2 dev.ion.Upd --target linux --out out/v2 --asset out/v2/version.txt
//   cp out/v1/Upd1-x86_64.AppImage /tmp/Upd.AppImage
//   ION_UPDATE_FROM=$PWD/out/v2/Upd2-x86_64.AppImage /tmp/Upd.AppImage
// Prints "updateLinux: version 1, installing", then "updateLinux: version 2".
import { installLinux } from "../src/update";
import { env, exit } from "std/process";
import { readFile } from "std/fs";

function main(): int32 {
	const read = readFile(`${env.get("APPDIR")}/usr/bin/resources/version.txt`);
	if (!read.ok) {
		console.log("FAIL: no version.txt (run from an AppImage built with --asset version.txt)");
		return 1;
	}
	const version = read.value.trim();
	if (version !== "1") {
		console.log(`updateLinux: version ${version}`);
		return 0;
	}
	console.log("updateLinux: version 1, installing");
	const r = installLinux(env.get("ION_UPDATE_FROM"), env.get("APPIMAGE"));
	if (!r.ok) console.log(`FAIL: ${r.error}`);
	return 1;
}

exit(main());
