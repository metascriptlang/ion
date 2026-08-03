// Custom URI schemes — replace file:// with proper-origin asset serving.
//
// Two schemes:
//   - <name>://localhost/<path>  — static file mapping registered via
//     registerStaticProtocol(name, baseDir). Loaded with origin
//     `<name>://localhost`, so pushState / localStorage / SW / COOP / COEP
//     all work like a real HTTPS origin.
//   - asset://localhost/<abs-path> — scoped disk read for files OUTSIDE the
//     bundle (file-picker results, user-selected media). Restricted to roots
//     declared via registerAssetScope().
//
// file:// is BLOCKED by ion's nav delegate — its opaque origin breaks every
// modern web platform feature that scopes by origin. Use ion:// or asset://.
//
// All registrations MUST happen BEFORE open(). The registry freezes at
// open() time; subsequent calls log a warning and return false.

import {
	ionRegisterStaticProtocol,
	ionRegisterAssetScope,
} from "./platform/bridge.h";

// Register `<scheme>://localhost/<path>` → `<baseDir>/<path>`.
//
// Path handling:
//   - Query string + fragment stripped before disk lookup
//   - URL-percent-decoded
//   - `..` segments rejected with 403
//   - MIME autodetected from extension (.html / .js / .css / .png / .woff2 / ...)
//   - Empty path → /index.html
//
// Returns true on success, false if called after open() or scheme/baseDir
// invalid (warning logged to stderr).
export function registerStaticProtocol(scheme: string, baseDir: string): boolean {
	return ionRegisterStaticProtocol(scheme, baseDir) === 1;
}

// Register the asset:// scheme with an allowlist of root paths. After
// registration, `asset://localhost/<abs-path>` serves the file at <abs-path>
// IF <abs-path> is under one of allowedRoots — otherwise returns 403.
//
// Typical use:
//   const picked = await openFile();  // /Users/.../photo.jpg
//   ion.registerAssetScope(["/Users/.../"]);     // before open()
//   ion.invoke("show.image", `asset://localhost${picked}`);
//
// Returns true on success, false if called after open() or already registered.
export function registerAssetScope(allowedRoots: string[]): boolean {
	const joined = allowedRoots.join("\n");
	return ionRegisterAssetScope(joined) === 1;
}
