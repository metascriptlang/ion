# Ion

A native desktop runtime for [MetaScript](https://github.com/metascript). Single-window webview shell with bidirectional IPC, native menu/tray/notifications/hotkeys, custom URI schemes (`ion://` / `asset://`), and full packaging pipeline (`.app` + `.dmg` + notarization). macOS v0 shipped; Windows reaches feature parity through Phase 4.5 (only NSIS packaging pending).

Designed as a thin glue layer — most of ion is platform-native code (Cocoa + WebKit + SDL3 on macOS), with MetaScript as the public API surface.

## What it is

- **Window + webview shell** (SDL3 + WKWebView). Load assets via `ion://localhost/...` (bundled), `asset://localhost/<abs-path>` (scoped disk file), `http(s)://` (dev server), or `data:`. `file://` is **blocked** — opaque-origin trap breaks pushState / localStorage / SW. See [CUSTOM-PROTOCOL.md](./CUSTOM-PROTOCOL.md).
- **JS↔MS IPC** with two ergonomic shapes:
  - Low-level: `invoke()` / `listen()` event passing.
  - High-level: `command()` Tauri-style `await window.ion.call("name", args)`.
- **Native chrome**: menu bar, tray icon, system notifications, global hotkeys, file dialog, deep links (`yourapp://`).
- **Security defaults**: invoke_key gates IPC against XSS injection, `forMainFrameOnly` keeps iframes out, DevTools env-gated, external links route to browser.
- **Packaging pipeline**: `.app` bundle with auto-bundled non-system dylibs, ad-hoc or Developer ID signing, Hardened Runtime + entitlements, DMG + notarization helpers.

## What it is not

- **Not a UI framework** — has no opinion on how pixels are drawn. Bring your own React, Vue, RNW, or static HTML.
- **Not a Chromium bundler** — uses the system WKWebView, no 100MB browser shipped per app.
- **Not a multi-window manager** — v0 is single-window. Add later if needed.
- **Not fully cross-platform yet** — macOS v0 is feature-complete; Windows reaches runtime parity through Phase 4.5 (only NSIS packaging pending); Linux not started.
- **Not a plugin framework** like Tauri — no capability ACL, no isolation iframe pattern. Apps that need those should use Tauri.

## Quick start

### Generate an Xcode project from MetaScript

The generator proof of concept evaluates a typed `project.ms` manifest with
Raiser, resolves plugins and target dependencies, and emits a deterministic
macOS or iOS Xcode application project:

```bash
tooling/generator/ion-generate examples/generator/project.ms /private/tmp/ion-generated
```

Nothing is built first: the wrapper runs the generator through `msc run
--target=raiser`. With no arguments it takes `project.ms` from the current
directory and writes to `out/xcode` beside it. Set `MSC` to pick a compiler
other than the `msc` on `PATH`. The output directory must not exist. See
[docs/PROJECT-GENERATOR.md](docs/PROJECT-GENERATOR.md) for the manifest API,
architecture, verification command and current POC boundaries.

### Build the demo

```bash
cd vendor/ion  # or ~/metascript/ion in older checkouts

# Run from source (dev mode)
msc run examples/helloWebview.ms

# Or the custom URI scheme demo — opens demo://localhost/index.html,
# proves pushState + localStorage + proper origin work
msc run examples/protocolDemo.ms

# Or build a release binary via the ion CLI
./bin/ion build examples/helloWebview.ms
# → out/release/helloWebview (~242 KB)
```

### Package as a `.app`

```bash
./bin/ion app out/release/helloWebview MyApp com.example.myapp \
  --out=out --url-scheme=myapp \
  --icon=assets/icon.icns \
  --asset=assets/tray-icon.png \
  --asset=examples/hello.html \
  --hardened --entitlements=assets/app.entitlements \
  --sign=-

# → out/MyApp.app (~2.7 MB)

./bin/ion dmg out/MyApp.app
# → out/MyApp.dmg (~1.2 MB)

# Optional: notarize for distribution
./bin/ion notarize out/MyApp.dmg NOTARY_PROFILE
```

### The `ion` CLI

`bin/ion` is a single binary built from `cli/main.ms` that orchestrates the
full build → bundle → DMG → notarize pipeline. Subcommands:

| Subcommand | Purpose |
|---|---|
| `ion build <entry>` | Compile MS source to a release binary (`--debug` for fast unoptimized) |
| `ion app <bin> <name> <bundle-id>` | Wrap binary as `.app` (icon, assets, sign, hardened, entitlements, dylib bundle) |
| `ion dmg <Foo.app>` | Wrap `.app` in UDZO-compressed DMG with /Applications symlink |
| `ion notarize <target> <profile>` | xcrun notarytool submit + wait + staple |
| `ion test` | Run all unit tests across `test/` and `command-builder/test/` |

Run `ion <command> --help` for command-specific options. Add `bin/` to your PATH
or symlink `bin/ion` to `/usr/local/bin/ion` for system-wide install.

The CLI itself is built on top of `command-builder/` — a small cac-inspired
CLI library written in MetaScript, also in this repo. To rebuild the CLI after
editing `cli/main.ms`:

```bash
msc build cli/main.ms --release --strip
cp out/release/main bin/ion
```

### Use ion from a MetaScript app

```ms
import { open, listen, invoke, command, runLoop } from "@metascript/ion";
import { installTrayImage, registerHotkeyKey, ModCmd, ModShift } from "@metascript/ion";

function main(): int32 {
	if (!open("My App", 1280 as int32, 800 as int32, "https://localhost:3000")) {
		return 1;
	}

	// Tauri-style command — JS does `await window.ion.call("greet", { name: "Sơn" })`
	command("greet", (argsJson) => {
		// parse argsJson, return JSON-encoded response
		return `"hello"`;
	});

	// Low-level event listener
	listen((name, payload) => {
		if (name === "tray.click") invoke("trayClicked", "ok");
	});

	installTrayImage("tray-icon.png");                      // bundled in Resources/
	registerHotkeyKey(ModCmd | ModShift, "L", 1 as int32);  // Cmd+Shift+L

	runLoop();  // blocks until window closes
	return 0;
}

main();
```

JS side, inside the loaded HTML:

```js
// Low-level event-based IPC
window.ion.invoke("ping", "hello");
window.ion.on("pong", (p) => console.log(p));

// Tauri-style request/response with await
const result = await window.ion.call("greet", { name: "Sơn" });
```

## API summary

| Module | Exports |
|---|---|
| `window` | `open`, `close`, `resourcePath` |
| `ipc` | `listen`, `invoke`, `eval`, `runLoop` (and `Handler` type) |
| `command` | `command` (and `Command` type) |
| `dialog` | `openFile` |
| `security` | `setContentProtected` |
| `protocol` | `registerStaticProtocol`, `registerAssetScope` |
| `tray` | `installTray`, `installTrayImage`, `uninstallTray` |
| `notify` | `notify` |
| `hotkey` | `registerHotkey`, `registerHotkeyKey`, `unregisterHotkey`, `keyCodeFromName` |
| `mods` | `ModCmd`, `ModShift`, `ModAlt`, `ModCtrl` |

All re-exported from the package root — `import { ... } from "@metascript/ion"` works for everything. Sub-module deep-imports are not stable.

## Custom URI schemes

ion serves bundled assets through **custom URI schemes** with proper origins instead of `file://`. The Tauri-style design avoids the [opaque-origin trap](https://html.spec.whatwg.org/multipage/origin.html#concept-origin-opaque) that breaks `history.pushState`, `localStorage` scoping, Service Workers, and COOP/COEP on `file://` URLs.

Two schemes ship by default:

| Scheme | Purpose | Example |
|---|---|---|
| `ion://localhost/<path>` | Bundled SPA assets. Auto-registered to `ionResourcePath()` (the `.app`'s `Contents/Resources/`) when you call `open()` with an `ion://` URL. | `ion.open("App", 1280, 800, "ion://localhost/index.html")` |
| `asset://localhost/<abs-path>` | Scoped disk read for files OUTSIDE the bundle (file-picker results, user images). Allowlist roots declared via `registerAssetScope()`. | `ion.registerAssetScope(["/Users/me/Pictures"])` then `<img src="asset://localhost/Users/me/Pictures/photo.jpg">` |
| `file://` | **BLOCKED** by ion's nav delegate. Use `ion://` or `asset://`. | — |

Register additional schemes (e.g. for app-specific routing) via `registerStaticProtocol`:

```ms
import { open, registerStaticProtocol, runLoop } from "@metascript/ion";

registerStaticProtocol("myapp", "/path/to/my/dist");
// → myapp://localhost/index.html now serves /path/to/my/dist/index.html
open("App", 1280 as int32, 800 as int32, "myapp://localhost/index.html");
runLoop();
```

Path semantics (handled inside ion):
- Query string + fragment stripped before disk lookup
- URL-percent-decoded
- `..` segments rejected with 403
- MIME autodetected from extension (.html, .js, .css, .png, .woff2, .wasm, etc.)
- Empty path → `/index.html`
- Calls to `registerStaticProtocol` MUST happen BEFORE `open()` — registry freezes then.

**Origin gotcha**: pages load with origin `<scheme>://localhost`. `fetch()` from the webview to external HTTPS needs `Access-Control-Allow-Origin` headers from those servers to include this origin. ion's `__ion__.invoke` IPC is unaffected.

Status: **macOS + Windows both shipped** in Phase 4.5 (2026-05-18). Linux waits on Linux foundation epic. See [CUSTOM-PROTOCOL.md](./CUSTOM-PROTOCOL.md) for landmine notes (Windows-specific WebView2 env-options gotchas).

## Repo structure

```
ion/
├── README.md
├── CLAUDE.md                 # design + working agreement
├── CHANGELOG.md
├── LICENSE                   # MIT
├── build.ms                  # MS package config
├── src/
│   ├── index.ms              # re-export hub
│   ├── window.ms             # open / close / resourcePath
│   ├── ipc.ms                # listen / invoke / eval / runLoop + build directives
│   ├── command.ms            # Tauri-style command()
│   ├── dialog.ms             # openFile
│   ├── security.ms           # setContentProtected
│   ├── protocol.ms           # registerStaticProtocol, registerAssetScope
│   ├── tray.ms               # status item
│   ├── notify.ms             # OS notifications
│   ├── hotkey.ms             # global hotkey + keycode mapping
│   ├── mods.ms               # modifier flag constants
│   ├── internal/
│   │   ├── cstr.ms           # cstring → MS string helper
│   │   └── jsEscape.ms       # JS string-literal escape
│   └── platform/
│       ├── bridge.h          # public C interface (cross-platform)
│       ├── common/           # plain C, every platform: queue, invoke_key, navpolicy, RNG, mime, protoReg
│       ├── macos/            # 15 .m files (Cocoa + WebKit + Carbon + URL-scheme handler)
│       └── windows/          # Win32 .c/.cpp files (WebView2 + custom-protocol + 8-version env options)
├── bin/
│   └── ion                   # compiled CLI (built from cli/main.ms)
├── cli/
│   └── main.ms               # CLI source — build/app/dmg/notarize/test subcommands
├── command-builder/
│   ├── index.ms              # cac-inspired CLI builder (used by cli/main.ms)
│   └── test/                 # 14 unit tests for the builder
├── scripts/
│   └── make-app.sh           # bundle helper called by `ion app` (will port to MS)
├── assets/
│   ├── icon.icns             # placeholder app icon
│   ├── tray-icon.png         # tray template image
│   └── app.entitlements
└── examples/
    ├── helloWebview.ms       # MS-side demo (loads ion://localhost/hello.html)
    ├── hello.html            # webview-side demo
    ├── ion.js                # JS bootstrap helper consumed by hello.html
    ├── protocolDemo.ms       # custom URI scheme demo (demo://localhost/index.html)
    └── demoAssets/           # SPA assets: index.html + app.js + style.css
```

## Security model

Three layers of defense against XSS in the loaded webview:

1. **`forMainFrameOnly: YES`** — the bootstrap script that creates `window.ion` is injected only into the main frame. iframes cannot reach the IPC API.
2. **invoke_key** — a 32-byte random hex token generated at app startup is baked into the bootstrap closure and required on every JS→MS message. Bypassing the bootstrap (raw `webkit.messageHandlers.ion.postMessage(...)`) is rejected.
3. **WKNavigationDelegate** — cross-origin user-clicked navigation is sent to the system browser, not loaded into the webview. The app can't be tricked into navigating to attacker pages.

Plus:
- **DevTools** are off by default. Enable in dev with `ION_DEVTOOLS=1`.
- **Content protection** (`setContentProtected(true)`) opt-in for sensitive windows — screen capture shows black.
- **Hardened Runtime + entitlements** supported in `make-app.sh --hardened --entitlements=...`.

What's intentionally NOT implemented (Tauri has them; ion doesn't because MyApp doesn't need them):

- Capability ACL system (per-command permission gating)
- Isolation iframe pattern with AES-GCM IPC encryption
- Plugin framework
- File system scope (FsScope)

If you ship arbitrary user-installable code in your webview (plugins, third-party widgets), use Tauri instead. Ion assumes the loaded bundle is yours.

## Status

| Platform | Status | Notes |
|---|---|---|
| macOS arm64 | **v0 shipped** | All v0 capabilities; MyApp's daily driver |
| macOS x86_64 | Untested | Should work via `--target` cross-compile |
| Windows x86_64 | **Phase 4** | Window + webview + IPC + Tauri commands + tray + notifications + file dialog + global hotkey all working. NSIS installer + code-signing pending (Phase 5) |
| Linux | Not started | Estimated ~1.5-2x macOS effort (GTK + WebKitGTK + AppIndicator) |

**Known Windows behavior:** ~1-2 s blank window on cold start (Edge process spawn + WebView2 COM init — standard for WebView2-based apps). A cross-platform splash screen is planned to mask this on both desktop and mobile.

### Cross-compile for Windows from macOS

Requires `zig` (`brew install zig`) — `zig cc` is the cross-compiler. No xwin, no extra toolchain installs.

```bash
msc build examples/helloWebview.ms --os=windows -f
# → helloWebview.exe (~9.9 MB)
```

Test in Parallels Desktop by either dropping the `.exe` into a shared folder
and double-clicking, or driving the VM from the host shell via
`prlctl exec <vm-name> -- <windows-path>`.

## Sizes

- Release binary stripped: 247 KB
- `.app` bundle (with bundled SDL3 dylib + icons): 2.7 MB
- DMG (UDZO compressed): 1.2 MB

For comparison, a minimal Tauri app on macOS bundles to ~3-8 MB.

## License

MIT — see [LICENSE](./LICENSE).
