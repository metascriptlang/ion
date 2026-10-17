// ion CLI — built on top of command-builder.
//
// Subcommands:
//   build     <entry.ms>            Compile to release binary (--release --strip).
//   app       ...                    Wrap binary as .app bundle (delegates to scripts/make-app.sh for now).
//   dmg       <Foo.app> [output]     Wrap .app in a UDZO-compressed .dmg.
//   notarize  <target> <profile>     Submit + wait + staple via xcrun notarytool.
//   test                              Run all ion + command-builder unit tests.
//
// Install:  msc install -g @metascript/ion@file:<this repo>   (build.ms `bin`)

import { cli, run } from "../src/cli/index";
import { exec, exit, cwd, env, cmdExists, findOnPath, platform } from "std/process";
import { exists, isFile, readDir, readFile, writeFile, copyFile, mkdir, removeAll, ensureDir, rename, chmod, symlink, dirname } from "std/fs";
import { expansionFile } from "std/meta";

const VERSION = "0.0.1";

const root = @comptime { return dirname(dirname(expansionFile())); };

// ---- helpers ---------------------------------------------------------------

function compiler(): string {
	const fromEnv = env.get("MSC");
	const tool = fromEnv.length > 0 ? fromEnv : "msc";
	const found = findOnPath(tool);
	if (found == "") die(`msc not found: ${tool} (put msc on PATH or set MSC)`);
	return found;
}

function msc(): string {
	return `"${compiler()}"`;
}

// exec captures output; echo it so the child's output stays visible, and map any
// failure (non-zero exit, signal, spawn) to a non-zero code.
function bash(cmd: string): int32 {
	const r = exec(cmd);
	if (r.ok) {
		if (r.value.length > 0) console.log(r.value);
		return 0;
	}
	if (r.error.output.length > 0) console.log(r.error.output);
	if (r.error.errorOutput.length > 0) console.log(r.error.errorOutput);
	return r.error.exitCode != 0 ? r.error.exitCode : 1;
}

function die(msg: string): void {
	console.log(`ion: ${msg}`);
	exit(1);
}

function basename(path: string): string {
	const sep1 = path.lastIndexOf("/");
	const sep2 = path.lastIndexOf("\\");
	const sep = sep1 > sep2 ? sep1 : sep2;
	return sep < 0 ? path : path.slice(sep + 1, path.length);
}

// Windows installer build — pure MS (file staging + NSI template render +
// makensis invocation). No bash; the mac side uses bash only because its
// otool / install_name_tool flow needs subprocess output capture which MS
// std/process doesn't expose yet. Windows path here just needs exit codes,
// so MS-native is cleaner.
function winApp(
	binary: string,
	name: string,
	bundleId: string,
	outDir: string,
	urlScheme: string,
	assets: string[],
	signCert: string,
	version: string
): void {
	if (!isFile(binary)) die(`binary not found: ${binary}`);

	const here = cwd();
	const loaderPath = `${root}/vendor/webview2/runtime/x64/WebView2Loader.dll`;
	if (!isFile(loaderPath)) die(`WebView2Loader.dll missing at ${loaderPath} (see vendor/webview2/README.md)`);

	// Two separate dirs so the installer payload doesn't accidentally pick up
	// the .nsi / .nsh build artifacts via `File /r`.
	const payloadDir = `${here}/out/_windows-payload`;
	const buildDir   = `${here}/out/_windows-build`;
	removeAll(payloadDir);
	removeAll(buildDir);
	if (!mkdir(payloadDir).ok) die(`mkdir failed: ${payloadDir}`);
	if (!mkdir(buildDir).ok)   die(`mkdir failed: ${buildDir}`);

	// ---- Stage binary + loader + assets into payload dir ----
	const mainBinaryName = basename(binary);
	copyFile(binary, `${payloadDir}/${mainBinaryName}`);
	copyFile(loaderPath, `${payloadDir}/WebView2Loader.dll`);

	if (assets.length > 0) {
		mkdir(`${payloadDir}/resources`);
		for (const asset of assets) {
			if (!exists(asset)) die(`asset not found: ${asset}`);
			copyFile(asset, `${payloadDir}/resources/${basename(asset)}`);
		}
	}

	// ---- Render NSI template into build dir ----
	const tplPath = `${root}/scripts/make-app-windows.nsi`;
	const tplRes = readFile(tplPath);
	if (!tplRes.ok) {
		die(`failed to read template: ${tplPath}`);
		return;
	}

	const outDirAbs = outDir.length > 0 ? outDir : `${here}/out`;
	ensureDir(outDirAbs);
	const outFileUnsigned = `${outDirAbs}/${name}-setup-unsigned.exe`;
	const outFileFinal    = `${outDirAbs}/${name}-setup.exe`;

	const stagingGlob = platform === "windows" ? payloadDir.replaceAll("/", "\\") + "\\*" : `${payloadDir}/*`;
	const rendered = tplRes.value
		.replaceAll("@@PRODUCTNAME@@",    name)
		.replaceAll("@@BUNDLEID@@",       bundleId)
		.replaceAll("@@VERSION@@",        version)
		.replaceAll("@@MAINBINARYNAME@@", mainBinaryName)
		.replaceAll("@@URLSCHEME@@",      urlScheme)
		.replaceAll("@@STAGINGGLOB@@",    stagingGlob)
		.replaceAll("@@OUTFILE@@",        outFileUnsigned);

	writeFile(`${buildDir}/installer.nsi`, rendered);
	copyFile(`${root}/scripts/utils.nsh`, `${buildDir}/utils.nsh`);

	// ---- Invoke makensis ----
	if (!cmdExists("makensis")) die("makensis not on PATH (NSIS: brew install makensis on macOS, nsis.sourceforge.io on Windows)");
	console.log("==> running makensis...");
	const nsiCode = bash(`cd "${buildDir}" && makensis -V2 installer.nsi`);
	if (nsiCode !== 0) die(`makensis failed (exit ${nsiCode})`);
	if (!isFile(outFileUnsigned)) die(`makensis produced no output at ${outFileUnsigned}`);

	// ---- Optional sign ----
	if (signCert.length > 0) {
		if (!cmdExists("osslsigncode")) die("--sign requires osslsigncode (brew install osslsigncode)");
		const pass = env.get("ION_SIGN_PASSWORD");
		const passArg = pass.length > 0 ? `-pass "${pass}"` : "";
		console.log(`==> signing with ${signCert}...`);
		const signCmd = `osslsigncode sign -pkcs12 "${signCert}" ${passArg} -n "${name}" -t http://timestamp.sectigo.com -in "${outFileUnsigned}" -out "${outFileFinal}"`;
		const signCode = bash(signCmd);
		if (signCode !== 0) die(`osslsigncode failed (exit ${signCode})`);
		removeAll(outFileUnsigned);
	} else {
		rename(outFileUnsigned, outFileFinal);
	}

	console.log(`==> built: ${outFileFinal}`);
}

const STUB_ICON_SVG = `<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256"><rect width="256" height="256" rx="48" fill="#3b82f6"/></svg>\n`;

// GTK4 and WebKitGTK 6.0 come from the user's system, so the AppDir holds only
// the binary, its resources and the desktop entry.
function linuxApp(
	binary: string,
	name: string,
	bundleId: string,
	outDir: string,
	urlScheme: string,
	icon: string,
	assets: string[]
): void {
	if (platform !== "linux") die("--target linux builds on a Linux host (appimagetool is Linux-only)");
	if (!cmdExists("appimagetool")) die("appimagetool not on PATH (github.com/AppImage/appimagetool/releases, 1.9.1)");

	const here = cwd();
	const exe = basename(binary);
	const appDir = `${here}/out/_linux-appdir`;
	removeAll(appDir);
	if (!ensureDir(`${appDir}/usr/bin`).ok) die(`mkdir failed: ${appDir}/usr/bin`);

	if (!copyFile(binary, `${appDir}/usr/bin/${exe}`).ok) die(`copy failed: ${binary}`);
	chmod(`${appDir}/usr/bin/${exe}`, 493);
	if (assets.length > 0) {
		mkdir(`${appDir}/usr/bin/resources`);
		for (const asset of assets) {
			if (!isFile(asset)) die(`asset not found: ${asset}`);
			copyFile(asset, `${appDir}/usr/bin/resources/${basename(asset)}`);
		}
	}
	if (!symlink(`usr/bin/${exe}`, `${appDir}/AppRun`).ok) die(`symlink failed: ${appDir}/AppRun`);

	if (icon.length > 0) {
		if (!isFile(icon)) die(`icon not found: ${icon}`);
		const ext = icon.endsWith(".svg") ? "svg" : icon.endsWith(".png") ? "png" : "";
		if (ext.length == 0) die(`icon must be .png or .svg: ${icon}`);
		copyFile(icon, `${appDir}/${bundleId}.${ext}`);
	} else {
		writeFile(`${appDir}/${bundleId}.svg`, STUB_ICON_SVG);
	}

	const mime = urlScheme.length > 0 ? `MimeType=x-scheme-handler/${urlScheme};\n` : "";
	writeFile(`${appDir}/${bundleId}.desktop`,
		`[Desktop Entry]\nType=Application\nName=${name}\nExec=${exe} %u\nIcon=${bundleId}\nCategories=Utility;\nTerminal=false\nStartupWMClass=${exe}\n${mime}`);

	const outDirAbs = outDir.length > 0 ? outDir : `${here}/out`;
	ensureDir(outDirAbs);
	const outFile = `${outDirAbs}/${name}-x86_64.AppImage`;
	removeAll(outFile);
	console.log("==> running appimagetool...");
	const code = bash(`ARCH=x86_64 appimagetool "${appDir}" "${outFile}"`);
	if (code !== 0) die(`appimagetool failed (exit ${code})`);
	if (!isFile(outFile)) die(`appimagetool produced no output at ${outFile}`);
	console.log(`==> built: ${outFile}`);
}

// ---- main ------------------------------------------------------------------

const app = cli("ion", VERSION);

// ---- build -----------------------------------------------------------------

// PROBE 2: ONE boolean option only — does that trigger SIGTRAP?
app.command("build <entry>", "Compile an MS entry to an optimized binary")
	.option("--debug", "Skip release optimization", false)
	.action((args) => {
		const entry = args.positional("entry");
		if (!exists(entry)) die(`entry not found: ${entry}`);
		const flags = args.flag("debug") ? "" : "--release --strip";
		const code = bash(`${msc()} build ${flags} "${entry}"`);
		if (code !== 0 as int32) exit(code as number);
	});

// ---- app -------------------------------------------------------------------

app.command("app <binary> <name> <bundle-id>", "Wrap a binary as a platform installer (.app on macOS, .exe NSIS on Windows, .AppImage on Linux)")
	.option("--target <target>", "Target platform: macos, windows or linux (default: host)", false)
	.option("--out <dir>", "Output directory (default: dirname of binary)", false)
	.option("--url-scheme <name>", "Register a URL scheme", false)
	.option("--icon <path>", "App icon (.icns on macOS, .png or .svg on Linux, ignored on Windows v0)", false)
	.option("--asset <path>", "Bundle a resource file (repeatable)", true)
	.option("--sign <identity>", "Code-sign (macOS identity / Windows .pfx)", false)
	.option("--hardened", "Enable Hardened Runtime (macOS, implies --sign)", false)
	.option("--entitlements <path>", "Path to .entitlements plist (macOS)", false)
	.option("--version <version>", "App version string (Windows VERSIONINFO)", false)
	.action((args) => {
		const binary = args.positional("binary");
		const name = args.positional("name");
		const bundleId = args.positional("bundle-id");
		if (!isFile(binary)) die(`binary not found: ${binary}`);

		// ---- Target dispatch ----
		const targetFlag = args.string("target", "");
		const target = targetFlag.length > 0
			? targetFlag
			: (platform === "windows" ? "windows" : platform === "linux" ? "linux" : "macos");

		if (target === "windows") {
			const assets = args.multi("asset");
			winApp(
				binary,
				name,
				bundleId,
				args.string("out", ""),
				args.string("url-scheme", ""),
				assets,
				args.string("sign", ""),
				args.string("version", "0.0.1")
			);
			return;
		}
		if (target === "linux") {
			linuxApp(
				binary,
				name,
				bundleId,
				args.string("out", ""),
				args.string("url-scheme", ""),
				args.string("icon", ""),
				args.multi("asset")
			);
			return;
		}
		if (target !== "macos") die(`unknown --target: ${target} (expected: macos | windows | linux)`);

		// Build the make-app.sh invocation. v0 of the CLI delegates the heavy
		// dylib + install_name_tool + codesign orchestration to the existing
		// bash script. Future: port to pure MS once subprocess output capture
		// lands in std/process.
		const outDir = args.string("out", "");
		const script = `${root}/scripts/make-app.sh`;
		if (!isFile(script)) die(`scripts/make-app.sh not found at ${script}`);

		let cmd = `"${script}" "${binary}" "${name}" "${bundleId}"`;
		if (outDir.length > 0) cmd = `${cmd} "${outDir}"`;

		const urlScheme = args.string("url-scheme", "");
		if (urlScheme.length > 0) cmd = `${cmd} --url-scheme=${urlScheme}`;

		const icon = args.string("icon", "");
		if (icon.length > 0) cmd = `${cmd} --icon="${icon}"`;

		const assets = args.multi("asset");
		for (const a of assets) cmd = `${cmd} --asset="${a}"`;

		const sign = args.string("sign", "");
		if (sign.length > 0) cmd = `${cmd} --sign="${sign}"`;

		if (args.flag("hardened")) cmd = `${cmd} --hardened`;

		const ent = args.string("entitlements", "");
		if (ent.length > 0) cmd = `${cmd} --entitlements="${ent}"`;

		const code = bash(cmd);
		if (code !== 0 as int32) exit(code as number);
	});

// ---- dmg -------------------------------------------------------------------

app.command("dmg <app-path>", "Wrap a .app bundle in a drag-install DMG")
	.option("--out <path>", "Output .dmg path (default: <app-dir>/<Name>.dmg)", false)
	.action((args) => {
		const appPath = args.positional("app-path");
		if (!exists(appPath)) die(`not found: ${appPath}`);

		// Derive defaults via shell — basename + dirname helpers in std/fs/path
		// exist but using shell keeps the substitution simple.
		const dmgPath = args.string("out", "");
		const dmgArg = dmgPath.length > 0 ? `"${dmgPath}"` : `"$(dirname "${appPath}")/$(basename "${appPath}" .app).dmg"`;
		const cmd = `set -e; APP="${appPath}"; DMG=${dmgArg}; NAME=$(basename "$APP" .app); STAGE=$(mktemp -d -t ion-dmg); cp -R "$APP" "$STAGE/$NAME.app"; ln -s /Applications "$STAGE/Applications"; rm -f "$DMG"; hdiutil create -volname "$NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null; rm -rf "$STAGE"; echo "built: $DMG ($(du -h "$DMG" | cut -f1))"`;

		const code = bash(cmd);
		if (code !== 0 as int32) exit(code as number);
	});

// ---- notarize --------------------------------------------------------------

app.command("notarize <target> <profile>", "Submit + wait + staple via xcrun notarytool")
	.action((args) => {
		const target = args.positional("target");
		const profile = args.positional("profile");
		if (!exists(target)) die(`not found: ${target}`);

		// .app must be zipped first; .dmg goes direct.
		const cmd = `set -e; TARGET="${target}"; PROFILE="${profile}"; EXT="$\{TARGET##*.}"; SUBMIT="$TARGET"; TMP=""; if [ "$EXT" = "app" ]; then TMP="$(dirname "$TARGET")/$(basename "$TARGET" .app).zip"; rm -f "$TMP"; ditto -c -k --keepParent "$TARGET" "$TMP"; SUBMIT="$TMP"; fi; echo "==> submitting $SUBMIT (1-10 minutes)..."; xcrun notarytool submit "$SUBMIT" --keychain-profile "$PROFILE" --wait; [ -n "$TMP" ] && rm -f "$TMP"; echo "==> stapling $TARGET"; xcrun stapler staple "$TARGET"; xcrun stapler validate "$TARGET"; TYPE="execute"; [ "$EXT" = "dmg" ] && TYPE="open"; spctl --assess --verbose=4 --type "$TYPE" "$TARGET" 2>&1 || true; echo "done."`;

		const code = bash(cmd);
		if (code !== 0 as int32) exit(code as number);
	});

// ---- test ------------------------------------------------------------------

app.command("test", "Run all ion + command-builder unit tests")
	.action((args) => {
		const dirs = ["test", "test/common", "src/cli/test"];
		let totalPass = 0;
		let totalFail = 0;

		for (const dir of dirs) {
			for (const file of readDir(`${root}/${dir}`)) {
				if (!file.endsWith(".ms")) continue;
				const path = `${root}/${dir}/${file}`;
				console.log(`==> ${path}`);
				const r = exec(`${msc()} test "${path}"`);
				const text = r.ok ? r.value : r.error.output + r.error.errorOutput;
				let result = "";
				for (const line of text.split("\n")) {
					if (line.includes(path) && (line.startsWith("✓") || line.startsWith("✗"))) result = line;
				}
				if (result.startsWith("✓")) {
					console.log(`    PASS ${result}`);
					totalPass += 1;
				} else {
					console.log("    FAIL");
					console.log(text);
					totalFail += 1;
				}
			}
		}
		if (totalPass + totalFail == 0) die(`no test files under ${root}`);
		console.log(`${totalPass} passed, ${totalFail} failed`);
		if (totalFail > 0) exit(1);
	});

// ---- dispatch --------------------------------------------------------------

run(app);
