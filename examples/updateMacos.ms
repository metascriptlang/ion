// OTA end to end on macOS: version 1.0.0 checks a manifest, refuses the artifact under a
// wrong public key, swaps in the 2.0.0 web bundle, then applies 2.0.0 over its own bundle
// and is relaunched.
// The relaunched app has no stdout, so it writes `updateMacos.relaunched` one directory above
// the bundle's, which stays writable when the bundle's own directory needs an admin prompt.
//
// Usage (macOS host, run from the repo root):
//   bash examples/updateMacos.sh
import { check, download, apply, checkWebview, applyWebview, UpdateConfig } from "../src/update";
import { argv, env, exit } from "std/process";
import { readFile, writeFile } from "std/fs";

const otherKey = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";

function bundlePath(): string {
	const at = argv[0].indexOf("/Contents/MacOS/");
	return at < 0 ? "" : argv[0].slice(0, at);
}

function config(publicKey: string, currentVersion: string, platform: string = "darwin-aarch64"): UpdateConfig {
	return {
		manifestUrl: env.get("ION_OTA_MANIFEST"),
		publicKey,
		currentVersion,
		channel: "stable",
		platform,
	};
}

function updateWeb(key: string, version: string): boolean {
	const found = checkWebview(env.get("ION_OTA_MANIFEST"), key, "stable", version);
	if (!found.ok || found.value === null) {
		console.log(`FAIL: checkWebview found no web bundle${found.ok ? "" : `: ${found.error}`}`);
		return false;
	}
	const dir = env.get("ION_OTA_WEB_DIR");
	const applied = applyWebview(config(key, version, "web"), found.value, dir, (done: int64, total: int64) => {});
	if (!applied.ok) {
		console.log(`FAIL: applyWebview: ${applied.error}`);
		return false;
	}
	const page = readFile(`${dir}/index.html`);
	console.log(`updateMacos: web bundle ${found.value.version}: ${page.ok ? page.value.trim() : "no index.html"}`);
	return page.ok && page.value.includes(found.value.version);
}

function main(): int32 {
	const bundle = bundlePath();
	if (bundle === "") {
		console.log("FAIL: not running from a .app bundle (launch it with open)");
		return 1;
	}
	const read = readFile(`${bundle}/Contents/Resources/version.txt`);
	if (!read.ok) {
		console.log("FAIL: no version.txt in the bundle");
		return 1;
	}
	const version = read.value.trim();
	if (version !== "1.0.0") {
		writeFile(`${bundle}/../../updateMacos.relaunched`, version);
		return 0;
	}

	const key = env.get("ION_OTA_KEY");
	const latest = check(config(key, "2.0.0"));
	if (!latest.ok || latest.value !== null) {
		console.log("FAIL: check at 2.0.0 should find no update");
		return 1;
	}
	const found = check(config(key, version));
	if (!found.ok) {
		console.log(`FAIL: check: ${found.error}`);
		return 1;
	}
	if (found.value === null) {
		console.log("FAIL: check at 1.0.0 found no update");
		return 1;
	}
	const info = found.value;
	console.log(`updateMacos: version ${version}, found ${info.version} (${info.artifactSize} bytes)`);

	const forged = download(config(otherKey, version), info, (done: int64, total: int64) => {});
	if (forged.ok) {
		console.log("FAIL: download accepted the artifact under another public key");
		return 1;
	}
	console.log(`updateMacos: other key refused: ${forged.error}`);
	if (!updateWeb(key, version)) return 1;

	console.log(`updateMacos: applying over ${bundle}`);
	const r = apply(config(key, version), info, bundle, (done: int64, total: int64) => {});
	if (!r.ok) console.log(`FAIL: apply: ${r.error}`);
	return 1;
}

exit(main());
