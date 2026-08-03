// Window lifecycle + bundle metadata.

import {
	ionInit, ionOpen, ionClose,
	ionResourcePath,
	ionRegisterStaticProtocol,
} from "./platform/bridge.h";

// Module-private flag — auto-register the `ion` scheme exactly once per
// process. Subsequent open() calls (e.g., switching URL) are no-ops.
let _ionSchemeRegistered: boolean = false;

// Open a window with an embedded webview pointed at `url`. v0: one window
// total — calling open() twice replaces the previous window.
//
// Supported schemes:
//   - ion://localhost/<path>     — bundled SPA, auto-registered to
//                                   ionResourcePath() on first call here
//   - asset://localhost/<path>   — scoped disk file (call registerAssetScope
//                                   first to declare allowed roots)
//   - http(s)://                 — dev server / external URL
//   - data:, about:              — allowed
//   - file://                    — BLOCKED by nav delegate (opaque-origin
//                                   trap). Use ion:// or asset:// instead.
//
// Cross-origin user-clicked http(s)/mailto links are intercepted by ion's
// nav delegate and routed to the user's default browser.
export function open(title: string, width: int32, height: int32, url: string): boolean {
	if (ionInit() === 0) return false;

	// Auto-register `ion://` → ionResourcePath() if app opens an ion:// URL
	// without having called registerStaticProtocol("ion", ...) explicitly.
	// Zero-config path for the common case "ship bundled SPA in the .app".
	if (!_ionSchemeRegistered && url.startsWith("ion://")) {
		const res = ionResourcePath();
		if (res !== "") {
			ionRegisterStaticProtocol("ion", res);
		}
		_ionSchemeRegistered = true;
	}

	return ionOpen(title, width, height, url) === 1;
}

export function close(): void {
	ionClose();
}

// Returns the .app bundle's Contents/Resources/ absolute path, or "" when
// running unbundled (dev binary). Use to construct file:// URLs for HTML/JS
// shipped inside the bundle:
//
//   const res = resourcePath();
//   const url = res !== ""
//     ? `file://${res}/index.html`     // bundled .app
//     : "http://localhost:8081";        // dev server fallback
export function resourcePath(): string {
	return ionResourcePath();
}

// Build a `file://` URL pointing at `<resourcePath>/<file>`, with the right
// shape for each platform's path conventions:
//
//   macOS:   /Users/.../Resources/x.html → file:///Users/.../Resources/x.html
//   Windows: C:\Program Files\App\resources\x.html
//            → file:///C:/Program%20Files/App/resources/x.html
//
// macOS POSIX paths drop straight into the URL. Windows native paths need
// backslashes flipped to forward, spaces percent-encoded, and a leading `/`
// before the drive letter (per RFC 8089 file-URL conventions).
//
// Returns "" if no bundled resources dir exists (dev mode); caller falls
// back to a dev URL.
export function resourceUrl(file: string): string {
	const res = resourcePath();
	if (res === "") return "";
	// Windows native path = drive letter + backslashes (e.g. `C:\Program Files\App`).
	// Convert to RFC 8089 file URL: leading `/` before drive, forward slashes,
	// percent-encoded spaces. macOS POSIX paths drop straight into `file://`.
	if (res.length >= 2 && res.slice(1, 2) === ":") {
		const fwd = res.replaceAll("\\", "/").replaceAll(" ", "%20");
		return `file:///${fwd}/${file}`;
	}
	return `file://${res}/${file}`;
}
