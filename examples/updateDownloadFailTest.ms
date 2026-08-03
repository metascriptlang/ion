// Failure-mode smoke: download() must REJECT a manifest signed with a key
// other than the one the app embeds. Real-world attack scenario: attacker
// controls OTA host, swaps manifest + uploads malicious artifact signed
// with their own key. Embedded pubkey is the only thing that blocks them.

import { check, download, UpdateConfig } from "../src/index";

function main(): int32 {
	const cfg: UpdateConfig = {
		manifestUrl:    "https://updates.example.com/api/myapp/manifest",
		// WRONG key (random valid Ed25519 pubkey). Signature on the artifact
		// was made with MyApp's real private key, so verification must fail.
		publicKey:      "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
		currentVersion: "v0.0.1",
		channel:        "stable",
		platform:       "darwin-aarch64",
	};

	const c = check(cfg);
	if (!c.ok)            { console.log(`check fail: ${c.error}`); return 1 as int32; }
	if (c.value === null) { console.log("no manifest available"); return 1 as int32; }

	const dl = download(cfg, c.value, (d: int64, t: int64) => {});
	if (dl.ok) {
		console.log("FAIL: download succeeded with wrong pubkey — signature check is broken!");
		return 1 as int32;
	}
	console.log(`PASS (rejected): ${dl.error}`);
	return 0 as int32;
}
