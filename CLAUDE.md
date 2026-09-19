# Ion — Native Desktop Runtime for MetaScript

> See [README.md](./README.md) for user-facing docs and quick-start. This file is the working agreement for anyone (Claude or human) editing ion's code.

Native desktop runtime layer. Provides window, webview, IPC, and native chrome (menu, tray, notifications, hotkeys, file dialog) as a single API. Not a UI framework — has no opinion about how pixels are drawn.

## Status

Last full source audit: **2026-08-03**. See [TODO.md](./TODO.md) for the verified
capability matrix and the publish-readiness gate — it is the source of truth for
"what actually exists". This section summarizes; TODO.md wins on conflict.

All three desktop platforms are wired and at functional parity for the core
runtime. Last recorded end-to-end verification for Windows and Linux was in a
Parallels VM around 2026-05-18/19; macOS is the daily driver (MyApp).

| | macOS | Windows | Linux |
|---|---|---|---|
| Window · webview · IPC · `command()` | ✅ | ✅ | ✅ |
| Custom URI scheme · nav routing | ✅ | ✅ | ✅ |
| Tray · notifications · file dialog · hotkey | ✅ | ✅ | ✅ |
| Content protection · keychain · `openExternal` | ✅ | ✅ | ✅ |
| Multi-window (`windowManager.ms`) | ✅ | ✅ | ✅ |
| Native menu bar | ✅ | ❌ | ❌ |
| Render surface | ✅ | ❌ | ❌ |
| OTA check / download / verify | ✅ | ✅ | ✅ |
| OTA apply (install + relaunch) | ✅ | ⛔ stub | ⛔ stub |

Native LOC: macOS 1715 · Windows 2119 · Linux 1508 · shared C 1392.
MetaScript LOC: 2016 across 20 modules.

What's implemented on macOS (full v0):
- Window + WKWebView shell on SDL3
- Bidirectional IPC (low-level event + Tauri-style `command()` Promise)
- Native menu bar, tray icon, OS notifications, global hotkey, file dialog
- Deep link URL scheme (cold-start + runtime, single-instance via OS)
- Persistent webview data store, external-link routing, content protection
- Security: invoke_key gate, `forMainFrameOnly`, env-gated DevTools, Hardened Runtime support
- Packaging: `.app` bundle (auto-bundles non-system dylibs), `.dmg`, ad-hoc + Developer ID sign, notarization helper

What's implemented on Windows (Phase 3 — functional v0 parity):
- Cross-compile pipeline (`zig cc` / `zig c++` via `--os=windows`, no extra installs)
- Win32 host window (`CreateWindowExW` + WndProc + PeekMessage pump)
- WebView2 child (`CreateCoreWebView2EnvironmentWithOptions` + controller async init, `LoadLibraryW` dynamic loader, no MSVC `.lib` link)
- Bidirectional IPC: `WebMessageReceived` → invoke_key gate → `ionEnqueueMessage` (`messaging.cpp`); MS → JS via `ExecuteScript` (`eval.cpp`)
- Tauri-style `command()` Promise
- External-link routing: `NavigationStarting` → `navpolicy` → `ShellExecuteW` (`nav.cpp`)
- Content protection via `SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE)`
- `localStorage` / `IndexedDB` persistence (WebView2 default user-data folder)
- `ionResourcePath` convention: `<exe-dir>/resources/`
- **Tray icon** (Shell_NotifyIcon) with image / text + tooltip; click → `tray.click` IPC
- **Notifications** (Shell_NotifyIcon balloon, rendered via modern Toast/Action Center pipeline on Win10/11); click → `notification.click` IPC with `id` payload
- **File dialog** (IFileOpenDialog COM); single-file, modal Show(), UTF-8 path or `""` on cancel
- **Global hotkey** (`RegisterHotKey` + WM_HOTKEY); ion bitmask → Win32 MOD_*, slot table at 16
- **Deep link** URL scheme (registry registration via NSIS installer; argv parse + named-mutex single-instance + WM_COPYDATA forward to primary; cold-start + runtime URLs both fire `"deeplink"` IPC)
- WebView2 SDK vendored under `vendor/webview2/` (version pinned 1.0.2849.39)

What's implemented on Linux:
- GTK3 host window + WebKitGTK webview (`webkit2gtk-4.1`), IPC, custom URI scheme
- Tray via libayatana-appindicator3, notifications via libnotify, file dialog via GtkFileChooser
- Global hotkey via `XGrabKey` (X11; XWayland best-effort)
- Keychain via libsecret (freedesktop Secret Service — GNOME Keyring / KWallet)
- Build flags resolved with `@comptime exec("pkg-config …")` in `src/ipc.ms`; `-lX11` named explicitly because `--as-needed` strips it otherwise
- Packaging: `scripts/make-deb.sh`, `scripts/make-flatpak.sh`

What's stubbed:
- **OTA `apply()` on Windows + Linux** — `platform/{windows,linux}/update/install.{c}` are explicit stubs returning `ION_UPDATE_NOT_IMPL`; `apply()` in `src/update.ms` guards on `cfg.platform.startsWith("darwin")` and refuses to call them. `check()` / `download()` / sha256 + ed25519 verification are pure MS and work everywhere.
- **Toast WinRT** — Windows notifications are balloon tips today (which Win10/11 render through the Toast/Action Center pipeline anyway). Proper `ToastNotificationManager` needs an AUMID from a Start Menu shortcut.

Known Windows quirks (not bugs):
- ~1-2 s white flash on cold start (first launch in a Windows session) — standard WebView2 latency (Edge process spawn + COM init). Deferred to a real cross-platform splash screen (covers mobile launch screen too).
- GUI subsystem strips `stdout`/`stderr` from the user terminal — redirect at launch (`app.exe > log.txt 2>&1`) for dev debugging.

What's not implemented anywhere:
- GPU surface — original design had void integration; deferred indefinitely (MyApp doesn't need)
- Linux port — planned, not started (~1.5-2x macOS effort per estimate)
- Capability ACL / isolation iframe / plugin framework / FS scope — Tauri-style framework features MyApp doesn't need; intentionally skipped to keep ion thin

## Position in the Stack

```
recompiler  — MetaScript compiler (C / JS / WASM backends)
ion         — desktop runtime (THIS PROJECT)
neon        — UI framework (consumes ion's webview, or native widgets on mobile)
```

Ion replaces SDL3's role as the windowing/event base layer for desktop MS apps, plus adds webview embedding, IPC, and native chrome.

## Project Structure

```
ion/
├── README.md
├── CLAUDE.md                 # this file
├── CHANGELOG.md
├── LICENSE
├── build.ms                  # MS package config
├── src/
│   ├── index.ms              # re-export hub (no logic)
│   ├── window.ms             # open / close / resourcePath
│   ├── ipc.ms                # listen / invoke / eval / runLoop + BUILD DIRECTIVES
│   ├── command.ms            # Tauri-style command()
│   ├── dialog.ms             # openFile (NSOpenPanel)
│   ├── security.ms           # setContentProtected
│   ├── tray.ms               # NSStatusItem
│   ├── notify.ms             # UNUserNotificationCenter
│   ├── hotkey.ms             # Carbon RegisterEventHotKey + key name → keycode
│   ├── mods.ms               # ModCmd/Shift/Alt/Ctrl
│   ├── internal/
│   │   ├── cstr.ms           # cstring → MS string helper
│   │   └── jsEscape.ms       # JS string-literal escape
│   └── platform/
│       ├── bridge.h          # public C interface, shared across all platforms
│       ├── common/           # plain C, compiled on every platform
│       │   ├── invokekey.c   # invoke_key gen + verify
│       │   ├── navpolicy.c   # external-link routing rules
│       │   ├── queue.c       # IPC message queue
│       │   └── randombytes.c # cryptographic RNG
│       ├── macos/            # 14 .m files split by concern, mirror MS-side structure
│       │   ├── state.h / state.m   # extern globals + storage + msg queue + invoke_key
│       │   ├── internal.h          # platform-private forward decls
│       │   ├── core/               # lifecycle.m, window.m
│       │   ├── webview/            # bootstrap.m, nav_delegate.m, eval.m, poll.m
│       │   ├── ipc/                # url_scheme.m
│       │   ├── chrome/             # menu.m, tray.m, notify.m, dialog.m
│       │   ├── input/              # hotkey.m
│       │   └── security/           # content_protect.m
│       └── windows/          # Phase 1 — Win32 skeleton, awaiting WebView2 (Phase 2)
│           ├── internal.h    # forward decls + WIN32_LEAN_AND_MEAN + windows.h
│           ├── state.h / state.c   # HWND + HINSTANCE + ionEnqueueMessage shim
│           ├── utf8.h / utf8.c     # UTF-8 ↔ UTF-16 conversion helpers
│           ├── core/               # lifecycle.c, window.c
│           ├── webview/            # poll.c (Phase 2 adds webview2.c + bootstrap)
│           ├── chrome/             # tray.c, notify.c, dialog.c (Phase 1 stubs)
│           ├── input/              # hotkey.c (Phase 4)
│           └── security/           # content_protect.c
├── bin/
│   └── ion                   # compiled CLI (built from cli/main.ms)
├── cli/
│   └── main.ms               # CLI entry — uses command-builder
├── command-builder/
│   ├── index.ms              # cac-inspired CLI library
│   └── test/                 # 14 unit tests
├── scripts/
│   └── make-app.sh           # bundle helper called by `ion app` (port to MS pending)
├── assets/
│   ├── icon.icns             # placeholder
│   ├── tray-icon.png
│   └── app.entitlements
├── examples/
│   ├── helloWebview.ms
│   └── hello.html
└── docs/                     # (empty — README is the doc for now)
```

## Naming Conventions

- **MS files**: camelCase (`window.ms`, never `gpu_surface.ms`)
- **C/ObjC functions exposed via bridge**: `ion`-prefixed camelCase (`ionOpen`, `ionInstallTrayImage`)
- **MS public API**: camelCase verb-first (`open`, `installTray`, `registerHotkeyKey`)
- **Types**: PascalCase (`Handler`, `Command`)
- **Constants**: PascalCase for modifier flags (`ModCmd`)
- **Private helpers**: lowercase + `_` prefix for module-private state (`_cmdNames`, `_cmdDispatchInstalled`)

## Build Directives — Important Quirk

The MS recompiler drops `@compile`/`@passC`/`@passL` directives from re-export-only files (files whose body is just `export { … } from "…"`). Build directives MUST live in a file whose body imports from the bridge header — currently `src/ipc.ms` is the canonical home.

If you split `ipc.ms` further or change which file holds the bridge directives, **also update the @compile/@passC/@passL block at the top of the new home**. Symptom of getting this wrong: `undefined symbol: _ionXxx` linker errors despite bridge.m existing on disk.

(Possibly a real recompiler bug — directives should be processed regardless of body content. Not yet filed; pattern works around it.)

## MS Compiler Bug Workarounds

See `the MetaScript compiler bug tracker` for the full bug tracker. Patterns ion uses to work around them:

### Bug 5 — Function values in containers

`Map<string, FunctionType>` codegens broken entry structs. `arr[i](…)` indexed-call codegens to non-callable `msClosure`. Lambda `return;` inside `listen()` callbacks trips return-type inference.

Workarounds in this codebase:
- **Parallel arrays** instead of map: `_cmdNames: string[]` + `_cmdFns: Command[]` in `command.ms`. Linear scan by name.
- **Pre-extract function value to local** before calling: `const fn = arr[i]; fn(args);` instead of `arr[i](args)`.
- **Standalone helper function** (not inline lambda) when early-return needed: `dispatchCall(payload)` extracted from inline `listen` callback.
- **For-of iteration** works correctly: `for (const h of handlers) h(name, payload)`.

When MS Bug 5 is fixed, can collapse `_cmdNames` + `_cmdFns` parallel arrays back into one `Map<string, Command>`.

## Build & Test

### Build matrix — where each target builds

| Target | Build host | Why |
|---|---|---|
| **macOS** (arm64/x86_64) | Mac directly | Native — has Cocoa, WebKit, SDL3, codesign tools. |
| **Windows** (x86_64) | **Mac via `--os=windows`** | zig cc bundles a full Windows GNU sysroot; no Windows host needed. WebView2 SDK headers vendored under `vendor/webview2/`. Recompiler auto-promotes the link driver from `zig cc` to `zig c++` whenever `.cpp` files are compiled (WebView2 controller / messaging / nav / protocol), pulling libcxxabi automatically. |
| **Linux** (arm64/x86_64) | **On the Linux box / VM directly** — NOT cross-compile from Mac | `platform/linux/state.h` pulls `<gtk/gtk.h>` + `<webkit2/webkit2.h>` and the ipc.ms `@platform("linux")` block calls `pkg-config --cflags gtk+-3.0 webkit2gtk-4.1 libnotify ayatana-appindicator3-0.1 libsecret-1` at `@comptime`. Those packages don't exist on macOS (no Homebrew GTK + WebKitGTK port that satisfies ion's APIs), so cross-compile from Mac stops at the first `#include <gtk/gtk.h>` regardless of toolchain. Build inside Parallels Ubuntu instead — that's the path the Phase 5 work was verified through. |

### Build the example (macOS host, native)
```bash
msc build examples/helloWebview.ms -f
```

### Cross-compile for Windows (from macOS)
```bash
msc build examples/helloWebview.ms --os=windows -f
# → /tmp/helloWebview.exe (~11.6 MB). Test by copying into a Parallels shared
# folder and double-clicking, or `prlctl exec <vm> -- <path>` via the
# Parallels CLI.
```

**Stale-cache gotcha:** if you've just done a Mac build and switch to
`--os=windows` (or vice-versa) without `-f` / cache clean, leftover `.o`
files keyed by source path (not target) can leak into the cross-target link
and produce a confusing `lld-link: undefined symbol __cxxabiv1::*` (linker
sees Mac Mach-O objects mixed with Windows COFF, or vice versa). Always
either `rm -rf out/debug/.cache` between target switches, or pass `-f` which
forces a clean recompile.

### Build for Linux (on a Linux host)
Inside a Linux VM (Ubuntu / Parallels arm64 used during Phase 5):
```bash
sudo apt-get install -y libgtk-3-dev libwebkit2gtk-4.1-dev libnotify-dev \
                        libayatana-appindicator3-dev libsecret-1-dev
msc build examples/helloWebview.ms -f
```
Do **not** run this with `--os=linux` from a Mac — `platform/linux/state.c`'s
GTK includes can't be resolved on a Mac host even with zig cc.

### How platform dispatch works
`@platform("windows") { ... }`, `@platform("macos") { ... }`, and
`@platform("linux") { ... }` blocks in `src/ipc.ms` decide which platform's
`.c` / `.m` / `.cpp` files get compiled — the recompiler filters them at
directive-collection time using `--os` (defaults to host).

### Cross-compile observability gotcha
Recompiler currently swallows linker stderr on failure (prints only
`error: link failed (exit N)` with no diagnostic). When a Windows
cross-compile dies at the link step, retrieve the actual error by replaying
the link command yourself:
```bash
zig cc -iquote"$(dirname "$(which ms)")/.." @out/debug/_link.rsp \
       -o /tmp/dbg.exe -lm 2>&1 | tail -30
```
`_link.rsp` is the response file the recompiler wrote alongside the output
binary path. Tail of that file lists the platform-specific linker flags
that were collected — quickest way to confirm the `@platform` filter pulled
in the right subset.

Build a release `.app` bundle:
```bash
./scripts/build-release.sh examples/helloWebview.ms
./scripts/make-app.sh out/release/helloWebview "MyApp" com.example.myapp out \
  --url-scheme=myapp --icon=assets/icon.icns \
  --asset=assets/tray-icon.png --asset=examples/hello.html \
  --hardened --entitlements=assets/app.entitlements --sign
```

Manual smoke test (no automated test suite yet — Solidify-6 in roadmap):
```bash
"out/MyApp.app/Contents/MacOS/helloWebview" > /tmp/ion-stdout.log 2>&1 &
sleep 4
grep -E "auto-probe|MS command|hotkey|reject" /tmp/ion-stdout.log
osascript -e 'tell application "System Events" to keystroke "l" using {command down, shift down}'
pkill -9 helloWebview
```

Expected output: `auto-probe: ipc alive`, `MS command addNumbers(100, 23)`, `[ion] IPC rejected: invalid invoke_key` (adversarial probe), `MS ← hotkey id=1`.

## Working Agreement (for Claude)

When editing ion:

- **Read [README.md](./README.md) first** for user-facing context.
- **Don't reintroduce GPU surface / void integration** — explicitly out of scope for v0.
- **Don't add Tauri-style features** MyApp doesn't need (capability ACL, isolation iframe, plugins, FS scope) without explicit user direction. Ion stays thin on purpose.
- **Keep files focused** — most src/*.ms is <100 lines. Split if a file approaches 200.
- **Manual-smoke-test after structural changes** using the script above. Until automated tests land, this is the safety net.
- **Brainstorm in Vietnamese** if the user does. Code, READMEs, and this file default to English.
- **Before starting Phase 4.5 (custom URI scheme)** — read [CUSTOM-PROTOCOL.md](./CUSTOM-PROTOCOL.md) first. It's the locked design spec + handoff brief. The brief is the explicit go-ahead for ion-source edits in that scope (per the `feedback_compiler-edits-need-explicit-go-ahead` memory rule — that rule applies to **recompiler** edits, not ion edits, but having a written brief keeps the bar consistent).

## Reference

- [CUSTOM-PROTOCOL.md](./CUSTOM-PROTOCOL.md) — Phase 4.5 handoff brief (custom URI schemes, file:// block).
- `~/metascript/refs/tauri/` — Tauri source for architectural reference. Read patterns; don't copy code (Rust, not portable).
- `the primary consumer app repo` — MyApp project context (ion's primary consumer).
- `the MetaScript compiler bug tracker` — MS bug tracker.
