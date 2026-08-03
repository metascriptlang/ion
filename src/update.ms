// Cross-platform OTA auto-update client for ion-based apps.
//
// Pulls manifest from an ion-ota service, verifies an Ed25519 signature on
// the artifact, atomically replaces the running binary, relaunches. See
// `docs/AUTO-UPDATE-SPEC.md` (client spec) and `docs/OTA.md` (server +
// protocol). Server already deployed at `updates.example.com`; MyApp is
// customer #1 — protocol is ion-owned.
//
// API:
//   check(cfg)                    → manifest fetch + version compare. Pure read.
//   download(cfg, info, onProg)   → fetch + sha256 + ed25519 verify → temp path.
//   apply(cfg, info, onProg)      → download() then platform install + relaunch.
//
// Apps decide cadence + dialog UX. Ion provides the mechanism.

import { fetch } from "std/core/fetch";
import { parseJson } from "std/serialize/json/parser";
import { getDynamicField, asString, asNumber, at, length } from "std/serialize/json/accessors";
import { writeFile, ensureDir, exists, removeAll, rename } from "std/fs";
import { exec } from "std/process";
import { sha256, fromBase64 } from "std/crypto";
import { ed25519Verify } from "std/crypto/ed25519";
import { isOlderThan } from "./internal/semver";

// Platform install bridge. Implementation lives under src/platform/macos/
// update/install.m — wired into the build via @platform("macos") @compile
// in ipc.ms. Linux + Windows install bridges are not implemented yet, so
// installMacOS() is the only platform path apply() can take today.
import {
	ionUpdateMountDmg,
	ionUpdateFindAppInVolume,
	ionUpdateReplaceApp,
	ionUpdateUnmountDmg,
	ionUpdateRelaunchAndExit,
} from "./platform/bridge.h";

// Caller passes this at every check/apply call. App embeds publicKey at
// compile time; everything else is per-runtime config (env, channel, etc).
export interface UpdateConfig {
	manifestUrl:    string;   // e.g. https://updates.example.com/api/myapp/manifest
	publicKey:      string;   // base64-encoded Ed25519 public key (32 bytes raw)
	currentVersion: string;   // SemVer; leading "v" optional
	channel:        string;   // "stable" | "beta" | ...
	platform:       string;   // "darwin-aarch64" | "linux-x86_64" | ...
}

// Filled by check() from the resolved asset for this platform. Caller hands
// the same value back to apply() — keeps the API state-free.
export interface UpdateInfo {
	version:            string;
	publishedAt:        string;
	releaseNotes:       string;
	artifactUrl:        string;
	artifactSize:       number;
	artifactHash:       string;  // "sha256:<hex>"
	artifactSignature:  string;  // "ed25519:<base64>"
}

// Result.err strings are dev-facing diagnostics, NOT user-facing copy. App
// catches + maps to a localized dialog message.

// Append ?channel=<x> to the manifest URL, preserving any existing query.
function appendChannel(url: string, channel: string): string {
	const sep = url.indexOf("?") >= 0 ? "&" : "?";
	return `${url}${sep}channel=${channel}`;
}

// Pull manifest, parse, find the asset for this platform, compare versions.
// Returns null when the app is already on the latest (or newer) version —
// app should treat null as "no update, no dialog".
export function check(cfg: UpdateConfig): Result<UpdateInfo | null, string> {
	const url = appendChannel(cfg.manifestUrl, cfg.channel);
	const r = fetch(url);
	if (!r.ok) return Result.err(`fetch failed: ${r.error.message}`);
	const resp = r.value;
	if (resp.status === 404) {
		// No releases on this channel yet — not an error.
		return Result.ok(null as unknown as UpdateInfo | null);
	}
	if (resp.status < 200 || resp.status >= 300) {
		return Result.err(`manifest http ${resp.status}: ${resp.body.slice(0, 200)}`);
	}

	const parsed = parseJson(resp.body);
	if (!parsed.ok) return Result.err(`manifest json parse: ${parsed.error}`);
	const root = parsed.value;

	const version = asString(getDynamicField(root, "version"));
	if (version === "") return Result.err("manifest missing version");

	// Older or same → no-op. SemVer aware (handles 'v' prefix + pre-release).
	if (!isOlderThan(cfg.currentVersion, version)) {
		return Result.ok(null as unknown as UpdateInfo | null);
	}

	// Find the asset entry matching our platform. Server schema (OTA.md):
	// assets is an array of { platform, url, size, hash, signature }.
	const assets = getDynamicField(root, "assets");
	const nAssets = length(assets);
	let matched: UpdateInfo | null = null as unknown as UpdateInfo | null;
	for (let i = 0; i < nAssets; i++) {
		const entry = at(assets, i);
		const plat  = asString(getDynamicField(entry, "platform"));
		if (plat !== cfg.platform) continue;
		matched = {
			version,
			publishedAt:       asString(getDynamicField(root,  "publishedAt")),
			releaseNotes:      asString(getDynamicField(root,  "releaseNotes")),
			artifactUrl:       asString(getDynamicField(entry, "url")),
			artifactSize:      asNumber(getDynamicField(entry, "size")),
			artifactHash:      asString(getDynamicField(entry, "hash")),
			artifactSignature: asString(getDynamicField(entry, "signature")),
		};
		break;
	}
	if (matched === null) {
		return Result.err(`no asset for platform "${cfg.platform}"`);
	}
	if (matched.artifactUrl === "" || matched.artifactSignature === "") {
		return Result.err("asset missing url or signature");
	}
	return Result.ok(matched as UpdateInfo | null);
}

// Match ion-ota's guessExt() — keep extension correct so platform installers
// (hdiutil for .dmg, msiexec for .msi, etc.) accept the file without rename.
function platformExt(platform: string): string {
	if (platform === "web") return "zip";
	if (platform.startsWith("darwin"))  return "dmg";
	if (platform.startsWith("windows")) return "exe";
	if (platform.startsWith("linux"))   return "tar.gz";
	return "bin";
}

// Strip a known prefix off a value. Returns "" if prefix isn't present.
function stripPrefix(s: string, prefix: string): string {
	if (!s.startsWith(prefix)) return "";
	return s.slice(prefix.length, s.length);
}

// Download artifact, verify sha256 + Ed25519 signature, write to a temp file.
// On success returns the absolute path; the caller (or apply()) consumes it.
// On failure NO temp file is left behind for callers to inspect — the goal is
// fail-closed: a bad artifact must never become a usable on-disk thing.
//
// `onProgress(bytesDone, bytesTotal)` is invoked at start (0, total) and end
// (total, total). Streaming progress requires a fetch streaming API which
// ion's std/core/fetch doesn't surface yet — single-shot is fine for v0.
export function download(cfg: UpdateConfig, info: UpdateInfo,
                         onProgress: (bytes: int64, total: int64) => void): Result<string, string> {
	// 1. Parse + validate the cryptographic metadata BEFORE network I/O so a
	//    malformed manifest fails fast and quietly.
	const expectedHash = stripPrefix(info.artifactHash, "sha256:");
	if (expectedHash === "") return Result.err("artifactHash missing sha256: prefix");

	const sigB64 = stripPrefix(info.artifactSignature, "ed25519:");
	if (sigB64 === "") return Result.err("artifactSignature missing ed25519: prefix");

	const sigRaw = fromBase64(sigB64);
	if (sigRaw.byteLength !== 64) {
		return Result.err(`signature decode: expected 64 bytes, got ${sigRaw.byteLength}`);
	}

	const pubRaw = fromBase64(cfg.publicKey);
	if (pubRaw.byteLength !== 32) {
		return Result.err(`publicKey decode: expected 32 bytes, got ${pubRaw.byteLength}`);
	}

	// 2. Download. ion's std fetch is single-shot (no streaming yet) so we
	//    pull the full body into memory before verifying. OK for typical
	//    desktop artifacts (~20-80 MB); revisit when stream API lands.
	onProgress(0 as int64, info.artifactSize as int64);

	const r = fetch(info.artifactUrl);
	if (!r.ok) return Result.err(`download fetch: ${r.error.message}`);
	const resp = r.value;
	if (resp.status < 200 || resp.status >= 300) {
		return Result.err(`download http ${resp.status}`);
	}
	const body = resp.body;

	// 3. Size check. Cheap. The hash check below is the real guarantee, but
	//    a size mismatch is a clearer error for ops than a hash mismatch.
	const got = body.byteLength as number;
	if (got !== info.artifactSize) {
		return Result.err(`size mismatch: manifest=${info.artifactSize}, downloaded=${got}`);
	}

	// 4. sha256 — Cloudflare/proxy/connection corruption shows here first.
	const h = sha256(body, "hex");
	if (!h.ok) return Result.err(`sha256 compute: ${h.error.message}`);
	if (h.value !== expectedHash) {
		return Result.err(`sha256 mismatch: expected ${expectedHash}, got ${h.value}`);
	}

	// 5. Ed25519 — the trust anchor. Public key is embedded in the app at
	//    build time, so only releases signed by the corresponding private
	//    key can pass. This is what protects against a compromised OTA host.
	if (!ed25519Verify(sigRaw, pubRaw, body)) {
		return Result.err("ed25519 signature verification failed");
	}

	// 6. Write to a versioned temp dir. The dir is unique per (platform,
	//    version) so concurrent / repeated apply() calls don't clobber each
	//    other. Caller is responsible for cleanup post-install.
	const tempDir = `/tmp/ion-update-${info.version}`;
	const ed = ensureDir(tempDir);
	if (!ed.ok) return Result.err(`ensureDir ${tempDir}: ${ed.error.message}`);

	const path = `${tempDir}/${cfg.platform}.${platformExt(cfg.platform)}`;
	const w = writeFile(path, body);
	if (!w.ok) return Result.err(`writeFile ${path}: ${w.error.message}`);

	onProgress(info.artifactSize as int64, info.artifactSize as int64);
	return Result.ok(path);
}

// One-shot update: download + verify + install + relaunch. Relaunch never
// returns on success — the current process is _exit(0)'d as part of swap.
// Callers that want to UI between download and install should call download()
// then installMacOS() (or future installLinux/Windows) directly.
//
// `destAppPath` is taken from the caller — for MyApp this is the running
// app's NSBundle path on macOS. ion intentionally does not introspect its own
// bundle because the same binary is reused for dev/test builds outside an
// installed .app.
export function apply(cfg: UpdateConfig, info: UpdateInfo, destAppPath: string,
                      onProgress: (bytes: int64, total: int64) => void): Result<void, string> {
	const dl = download(cfg, info, onProgress);
	if (!dl.ok) return Result.err(dl.error);
	// Only macOS is wired today. Linux + Windows ship as `installLinux` /
	// `installWindows` in later phases (AppImage atomic replace + NSIS
	// uninstall-then-install respectively). Selecting by cfg.platform here
	// keeps the public API stable across that future split.
	if (cfg.platform.startsWith("darwin")) {
		return installMacOS(dl.value, destAppPath);
	}
	return Result.err(`apply() not implemented for platform "${cfg.platform}" yet`);
}

// =========================================================================
// Webview hot update — zero-friction channel for HTML/JS/CSS updates.
//
// Same OTA manifest + trust anchor (ed25519). Difference vs native:
//   - asset.platform = "web", artifact = .zip
//   - no admin auth, no /Applications swap
//   - target is a webview-content directory (typically
//     <App>.app/Contents/Resources/web). After swap, caller invokes
//     ion's eval("window.location.reload()") so the running webview
//     picks up the new files via ion://localhost/.
//
// Apps should register ion://localhost/ to point at this same directory
// via `registerStaticProtocol("ion", destWebviewDir)` so hot push and
// native resources stay decoupled (native icons / tray images live one
// level up at Resources/).
// =========================================================================

// Check the OTA manifest for a webview asset (platform "web") newer than
// `currentVersion`. Pass the version number tracked separately from the
// native shell version — webview and native usually update on different
// cadences, so apps maintain two `currentVersion`s.
export function checkWebview(manifestUrl: string, publicKey: string,
                              channel: string, currentVersion: string): Result<UpdateInfo | null, string> {
	return check({
		manifestUrl,
		publicKey,
		currentVersion,
		channel,
		platform: "web",
	});
}

// Apply webview bundle: download .zip → verify → unzip into a staged dir →
// atomic rename swap (old aside, new in) → cleanup old. Caller is
// responsible for reloading the webview (eval window.location.reload).
//
// destDir is the LIVE webview directory — the swap replaces its contents
// atomically. Sibling paths used during the swap:
//   <destDir>/../<basename>.staged   — fresh files unzipped here first
//   <destDir>/../<basename>.old      — previous version (deleted at end)
// destDir's parent dir must exist + be writable by the caller (no admin).
export function applyWebview(cfg: UpdateConfig, info: UpdateInfo, destDir: string,
                              onProgress: (bytes: int64, total: int64) => void): Result<void, string> {
	const dl = download(cfg, info, onProgress);
	if (!dl.ok) return Result.err(dl.error);

	// Stage: empty .staged sibling. Don't unzip into the live dir — a torn
	// extract there is observable to a still-running webview.
	const stagedDir = `${destDir}.staged`;
	const oldDir    = `${destDir}.old`;

	if (exists(stagedDir)) {
		const r = removeAll(stagedDir);
		if (!r.ok) return Result.err(`pre-clean staged: ${r.error.message}`);
	}
	const ed = ensureDir(stagedDir);
	if (!ed.ok) return Result.err(`mkdir staged: ${ed.error.message}`);

	// /usr/bin/unzip on macOS, Linux. Windows port (Phase later) shells out
	// to PowerShell `Expand-Archive` or vendors a tiny zip extractor.
	const uz = exec(`/usr/bin/unzip -qq -o '${dl.value}' -d '${stagedDir}'`);
	if (!uz.ok) {
		removeAll(stagedDir);
		return Result.err(`unzip: ${uz.error.message}`);
	}

	// Atomic two-rename swap. The window where destDir is missing (between
	// the two renames) is bounded to a single inode-level rename — ion's
	// custom URI scheme handler returns 404 during that window, which the
	// webview tolerates as a transient fetch fail. If step 2 fails we
	// recover by renaming oldDir back.
	if (exists(oldDir)) {
		const r = removeAll(oldDir);
		if (!r.ok) {
			removeAll(stagedDir);
			return Result.err(`pre-clean old: ${r.error.message}`);
		}
	}
	if (exists(destDir)) {
		const r = rename(destDir, oldDir);
		if (!r.ok) {
			removeAll(stagedDir);
			return Result.err(`rename live → old: ${r.error.message}`);
		}
	}
	const swap = rename(stagedDir, destDir);
	if (!swap.ok) {
		// Best-effort recovery: put oldDir back so the app keeps working
		// on the previous bundle instead of an empty path.
		if (exists(oldDir)) rename(oldDir, destDir);
		removeAll(stagedDir);
		return Result.err(`rename staged → live: ${swap.error.message}`);
	}

	// Old version succeeded out — drop it. Failure here is non-fatal: a
	// stale `.old` sibling just leaks a few MB of disk. Cleanup runs again
	// at the start of the next apply.
	removeAll(oldDir);
	return Result.ok(null);
}

// Install a verified .dmg into destAppPath, then relaunch. Single admin
// prompt for the rm + ditto. NEVER returns on success — the current process
// is _exit(0)'d inside the relaunch helper. Returns Result.err on:
//   - mount failure (corrupt .dmg or hdiutil refused)
//   - no .app at the volume root
//   - user clicked Cancel on the auth dialog (recoverable; app stays open)
//   - any other privileged-op failure
export function installMacOS(dmgPath: string, destAppPath: string): Result<void, string> {
	const mountPath = ionUpdateMountDmg(dmgPath);
	if (mountPath === "") return Result.err(`hdiutil attach failed for ${dmgPath}`);

	const srcApp = ionUpdateFindAppInVolume(mountPath);
	if (srcApp === "") {
		ionUpdateUnmountDmg(mountPath);
		return Result.err(`no .app at root of mounted ${dmgPath}`);
	}

	const rr = ionUpdateReplaceApp(srcApp, destAppPath);
	if (rr === -3) {
		ionUpdateUnmountDmg(mountPath);
		return Result.err("user cancelled the admin authorization");
	}
	if (rr !== 0) {
		ionUpdateUnmountDmg(mountPath);
		return Result.err(`replace failed rc=${rr}`);
	}

	// rm + ditto succeeded — the .dmg is no longer needed. Detach quietly;
	// even if detach errors (e.g. user unmounted via Finder mid-flow) we
	// still proceed to relaunch, since the install itself is committed.
	ionUpdateUnmountDmg(mountPath);

	// Hands off to the relaunch helper and exits this process. Never returns.
	ionUpdateRelaunchAndExit(destAppPath);
	// Unreachable — left for compiler control-flow happiness.
	return Result.err("relaunch returned unexpectedly (this should never happen)");
}
