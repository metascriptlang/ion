# Ion

A native desktop runtime for [MetaScript](https://github.com/metascript). Windows whose content the app builds, webviews as components with bidirectional IPC, native menu/tray/notifications/hotkeys, custom URI schemes (`ion://` / `asset://`), and full packaging pipeline (`.app` + `.dmg` + notarization). macOS v0 shipped; Windows reaches feature parity through Phase 4.5 (only NSIS packaging pending).

Designed as a thin glue layer — most of ion is platform-native code (Cocoa + WebKit + SDL3 on macOS), with MetaScript as the public API surface.

## Where Ion sits

A game engine owns the window, the events, the frame loop, the renderer and the build in one piece. MetaScript splits that into three pieces that compose:

- **Ion** owns the process and the window: the window and its compositor root, raw input, the frame clock, the webview engine and its IPC, native chrome, the project generator, build and packaging.
- **Neon** is the UI framework: it receives Ion's events, runs the reactive tree and drives a renderer through its host contract.
- **Void** draws GPU pixels into the surface Ion hands out, and owns no window and no loop when embedded.

Apps are built Ion → Neon → Void: Ion holds no UI and does no hit-testing; Neon places its views, Void areas and webviews in the window and routes input to them. Ion imports neither Neon nor Void. The full split, per concern, is in `neon/docs/VISION.md`; the window and webview contract is [docs/WINDOW-CONTENT.md](docs/WINDOW-CONTENT.md).

## What it is

- **Empty windows and webview components.** A window is a native root the app builds on (DirectComposition on Windows, the contentView on macOS, a GtkFixed on Linux); a webview is one node in it, with IPC routed by its label. Load assets via `ion://localhost/...` (bundled), `asset://localhost/<abs-path>` (scoped disk file), `http(s)://` (dev server), or `data:`. `file://` is **blocked** — opaque-origin trap breaks pushState / localStorage / SW. See [CUSTOM-PROTOCOL.md](./CUSTOM-PROTOCOL.md).
- **JS↔MS IPC** with two ergonomic shapes:
  - Low-level: `emit()` / `listen()` event passing.
  - High-level: `command()` Tauri-style `await window.ion.call("name", args)`.
- **Native chrome**: menu bar, tray icon, system notifications, global hotkeys, file dialog, deep links (`yourapp://`).
- **Security defaults**: invoke_key gates IPC against XSS injection, `forMainFrameOnly` keeps iframes out, DevTools env-gated, external links route to browser.
- **Packaging pipeline**: `.app` bundle with auto-bundled non-system dylibs, ad-hoc or Developer ID signing, Hardened Runtime + entitlements, DMG + notarization helpers.

## What it is not

- **Not a UI framework** — has no opinion on how pixels are drawn. Neon draws the UI; a webview holds HTML as one component of it.
- **Not a Chromium bundler** — uses the system WKWebView, no 100MB browser shipped per app.
- **Not a multi-window manager** — v0 is single-window. Add later if needed.
- **Not fully cross-platform yet** — macOS v0 is feature-complete; Windows reaches runtime parity through Phase 4.5 (only NSIS packaging pending); Linux not started.
- **Not a plugin framework** like Tauri — no capability ACL, no isolation iframe pattern. Apps that need those should use Tauri.

## Quick start

### Generate an Xcode, Gradle or Visual Studio project from MetaScript

The generator proof of concept evaluates a typed `project.ms` manifest with
Raiser, resolves plugins and target dependencies, and emits a deterministic
macOS or iOS Xcode application project, an Android Gradle project
(`examples/generatorAndroid/project.ms`), or a Windows Visual Studio solution
(`examples/helloWebviewProject.ms`):

```bash
ion generate examples/generator/project.ms /private/tmp/ion-generated
```

`ion` is the package command `msc install -g @metascript/ion@file:<checkout>`
puts on `PATH`; it runs the generator through `msc run --target=raiser`. With no arguments it takes `project.ms` from the current
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
ion build examples/helloWebview.ms
# → out/release/helloWebview (~242 KB)
```

### Package as a `.app`

```bash
ion app out/release/helloWebview MyApp com.example.myapp \
  --out=out --url-scheme=myapp \
  --icon=assets/icon.icns \
  --asset=assets/tray-icon.png \
  --asset=examples/hello.html \
  --hardened --entitlements=assets/app.entitlements \
  --sign=-

# → out/MyApp.app (~2.7 MB)

ion dmg out/MyApp.app
# → out/MyApp.dmg (~1.2 MB)

# Optional: notarize for distribution
ion notarize out/MyApp.dmg NOTARY_PROFILE
```

### The `ion` CLI

`ion` is the package command declared in `build.ms` (`bin`), built from
`cli/main.ms`. Install it once from the checkout; `msc` builds it on first use
and rebuilds it after `cli/main.ms` changes:

```bash
msc install -g @metascript/ion@file:$PWD
```

It orchestrates the build → bundle → DMG → notarize pipeline and generates
native projects. Subcommands:

| Subcommand | Purpose |
|---|---|
| `ion build <entry>` | Compile MS source to a release binary (`--debug` for fast unoptimized) |
| `ion app <bin> <name> <bundle-id>` | Wrap binary as `.app` (icon, assets, sign, hardened, entitlements, dylib bundle) |
| `ion dmg <Foo.app>` | Wrap `.app` in UDZO-compressed DMG with /Applications symlink |
| `ion notarize <target> <profile>` | xcrun notarytool submit + wait + staple |
| `ion test` | Run all unit tests across `test/`, `test/common/` and `src/cli/test/` |
| `ion generate [manifest] [output]` | Generate an Xcode, Gradle or Visual Studio project from a `project.ms` manifest |

Run `ion <command> --help` for command-specific options. Scripts, templates and
the generator are read from the checkout `ion` was installed from; output goes
under the current directory.

The CLI itself is built on top of `command-builder/` — a small cac-inspired
CLI library written in MetaScript, also in this repo.

### Use ion from a MetaScript app

Apps are written in Neon, which builds the window's content. Underneath, this is what Neon does
with Ion; `examples/content/page.ms` is the smallest complete host (one webview filling the
window) and `examples/nativeContent.ms` mixes native panels with a webview.

```ms
import { createWindow, defaultOptions, createWebview, webviewNode, windowRoot,
         setWebviewBounds, command, listen, emit, runLoop } from "@metascript/ion";

const win = createWindow("main", defaultOptions("My App", 1280 as int32, 800 as int32));
const web = createWebview(win, "main", "ion://localhost/index.html");
// The app parents webviewNode(web) under windowRoot(win) in its own tree,
// gives it bounds with setWebviewBounds, and forwards pointer input to it.

// Tauri-style command — JS does `await window.ion.call("greet", { name: "Sơn" })`
command("greet", (argsJson) => `"hello"`);

// Low-level event listener; replies go to the webview that sent the message
listen((name, payload) => {
	if (name === "ping") emit(web, "pong", payload);
});

runLoop();  // blocks until the window closes
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
| `windowManager` | `requestSingleInstance`, `createWindow` (with `panel: true` a macOS launcher panel that takes keys without activating the app), `windowRoot`, `windowDevice`, `commit`, `focusContent`, `setImeRect`, `setCursor`, `setOptionAsAlt`, `requestUserAttention`, `beep`, frame policy, `onWindowEvent` with `preventClose` (a close-requested handler keeps the window open) |
| `exit` | `onExitRequested`, `preventExit`: Cmd+Q, the Quit item or a quit Apple Event asks the handlers before the loop ends (macOS) |
| `webview` | `createWebview`, `webviewNode`, `setWebviewBounds`, `forwardPointer`, `focusWebview`, `navigate`, `evalJs`, `emit`, `emitTo`, `emitAll` |
| `input` | `onPointer`, `onKey`, `onText`, `onImePreedit`, `onFocus`, `onResize`, `onFrame` |
| `ipc` | `listen`, `messageWebviewId`, `runLoop` (and `Handler` type) |
| `window` | `resourcePath`, `resourceUrl`, `readResource` (the bytes of a bundled file; the one way to read an asset on Android) |
| `command` | `command` (and `Command` type) |
| `dialog` | `openFile` |
| `security` | `setContentProtected` |
| `protocol` | `registerStaticProtocol`, `registerAssetScope` |
| `tray` | `installTray`, `installTrayImage`, `uninstallTray` |
| `menu` | `setAppMenu` with `Submenu` and `MenuItem.action` / `.standard` / `.separator`; an action item delivers `"menu.click"` with its id to `listen` (macOS only) |
| `font` | `findSystemFonts(codepoint, { presentation, weight, italic, family })` returns `{ path, index }` of every installed font file that draws the codepoint, best first, or `[]` (macOS only) |
| `notify` | `notify` |
| `hotkey` | `registerHotkey`, `registerHotkeyKey`, `unregisterHotkey`, `keyCodeFromName` |
| `mods` | `ModCmd`, `ModShift`, `ModAlt`, `ModCtrl` |

All re-exported from the package root — `import { ... } from "@metascript/ion"` works for everything. Sub-module deep-imports are not stable.

## Single instance

An Ion app is multi-instance by default: a second launch (or a deep link) starts a new process, which sees its URL as its cold-start `deeplink`. An app that wants one instance asks for it before the first window, as Electron's `requestSingleInstanceLock` does:

```ts
import { requestSingleInstance, createWindow, runLoop } from "@metascript/ion"
import { exit } from "std/process"

if (!requestSingleInstance()) exit(0)   // second launch: URL forwarded, first window raised
createWindow("main", defaultOptions("MyApp", 1280 as int32, 800 as int32))
runLoop()
```

`false` means an earlier process holds the lock; its `listen` handler already received the forwarded `deeplink`, and Ion does not exit, the app decides. Calling it after the first window throws. macOS always answers `true`, LaunchServices keeps one instance per bundle.

## Custom URI schemes

ion serves bundled assets through **custom URI schemes** with proper origins instead of `file://`. The Tauri-style design avoids the [opaque-origin trap](https://html.spec.whatwg.org/multipage/origin.html#concept-origin-opaque) that breaks `history.pushState`, `localStorage` scoping, Service Workers, and COOP/COEP on `file://` URLs.

Two schemes ship by default:

| Scheme | Purpose | Example |
|---|---|---|
| `ion://localhost/<path>` | Bundled SPA assets. Auto-registered to `ionResourcePath()` (the `.app`'s `Contents/Resources/`) when the first webview loads an `ion://` URL. | `createWebview(win, "main", "ion://localhost/index.html")` |
| `asset://localhost/<abs-path>` | Scoped disk read for files OUTSIDE the bundle (file-picker results, user images). Allowlist roots declared via `registerAssetScope()`. | `ion.registerAssetScope(["/Users/me/Pictures"])` then `<img src="asset://localhost/Users/me/Pictures/photo.jpg">` |
| `file://` | **BLOCKED** by ion's nav delegate. Use `ion://` or `asset://`. | — |

Register additional schemes (e.g. for app-specific routing) via `registerStaticProtocol`:

```ms
import { registerStaticProtocol, createWebview } from "@metascript/ion";

registerStaticProtocol("myapp", "/path/to/my/dist");
// → myapp://localhost/index.html now serves /path/to/my/dist/index.html
const web = createWebview(win, "main", "myapp://localhost/index.html");
```

Path semantics (handled inside ion):
- Query string + fragment stripped before disk lookup
- URL-percent-decoded
- `..` segments rejected with 403
- MIME autodetected from extension (.html, .js, .css, .png, .woff2, .wasm, etc.)
- Empty path → `/index.html`
- Calls to `registerStaticProtocol` MUST happen before the first `createWebview` — the registry freezes then.

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
