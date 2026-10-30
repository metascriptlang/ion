// Bundle metadata.

import { ionResourcePath, ionReadAsset, ionAssetStatus } from "./platform/bridge.h";
import { readFileBytes } from "std/fs";
import { join } from "std/fs/path";

when (ios) {
	@compile("./platform/ios/core/resource.m", "-fobjc-arc");
	@passL("-framework Foundation");
}

when (android) {
	@compile("./platform/android/core/resource.c");
	@passL("-landroid");
}

// Returns the .app bundle's Contents/Resources/ absolute path (the flat .app itself on iOS), or "" when
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

// The bytes of a file shipped with the app (`Target.assets`), by its path inside the bundle:
//
//   const font = readResource("assets/JetBrainsMonoNL-Regular.ttf");
//
// On Android the file stays inside the APK, so `resourcePath()` ("/android_asset") is no path to
// open; read through this instead.
export function readResource(path: string): Result<uint8[], string> {
	when (android) {
		const bytes = ionReadAsset(path);
		const status = ionAssetStatus();
		if (status < 0) return Result.err("no Android AssetManager: build the app through ion generate");
		if (status == 0) return Result.err("no asset " + path);
		return Result.ok(bytes.asBytes().slice(0));
	} else {
		const root = resourcePath();
		if (root === "") return Result.err("no resource directory: the app runs unbundled");
		const read = readFileBytes(join(root, path));
		if (!read.ok) return Result.err("cannot read resource " + path + ": " + read.error.message);
		return Result.ok(read.value);
	}
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
