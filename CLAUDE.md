# Ion — native desktop runtime for MetaScript

Windows whose content the app builds, webview components and their IPC, and native chrome (menu, tray, notifications, hotkeys, file dialog, keychain, updater) behind one API. Not a UI framework: ion has no opinion about how pixels are drawn. Open source, MIT. Neon and Lightcube consume it; ion imports neither.

Workspace rules (toolchain, compiler boundary, arcs and cards) are in `~/metascript/CLAUDE.md` and are not repeated here.

## Where the truth is

| question | file |
|---|---|
| what exists per platform, what is a stub | [`TODO.md`](./TODO.md), the capability matrix; it wins over every other text |
| user-facing API and quick start | [`README.md`](./README.md) |
| custom URI schemes, `file://` block | [`CUSTOM-PROTOCOL.md`](./CUSTOM-PROTOCOL.md) |
| multi-window, window content and webviews, project generator | `docs/MULTI-WINDOW.md`, `docs/WINDOW-CONTENT.md`, `docs/PROJECT-GENERATOR.md` |
| architectural precedent | `~/metascript/refs/tauri/` — read patterns, do not copy code |

This file holds no status table. A capability claim is edited in `TODO.md`, after running it.

## Layout

- `src/*.ms` — the public API, one concern per file, re-exported by `src/index.ms`. `src/cli/` is the CLI library, `cli/main.ms` the `ion` CLI, `tooling/generator/` the project generator (`bin/ion-generate`).
- `src/platform/bridge.h` — the one C surface every platform implements. `common/` is plain C built everywhere; `macos/` (`.m`), `windows/` (`.c` + `.cpp`, WebView2 vendored in `vendor/webview2/`), `linux/` (GTK4 + WebKitGTK 6.0) mirror each other by concern: `core/ webview/ chrome/ input/ security/ update/`.
- Put a C source's build directives (`@compile` / `@passC` / `@passL`, per platform inside `when (macos) { … }`, `when (linux) { … }`, `when (windows) { … }`) in the module whose externs call it: `src/ipc.ms` for the window host and its platform sources, `src/audio.ms` for audio. msc links a module's directives only when something imported from that module is used, so an audio-only app would otherwise link without `audio.c` (measured 2026-10-15 on `wt/ion-audio`). A branch not taken is never type-checked. `@platform` no longer exists.
- A relative `-I` in `@passC` resolves against the directory of the module that declares it (`src/`), not against the build directory.

## Commands

```bash
msc check src/index.ms                      # type-check the library
msc test test/mods.ms                       # one unit test file; test/*.ms and test/common/*.ms
msc build examples/helloWebview.ms          # macOS host build
msc build examples/helloWebview.ms --os=windows -f   # cross-compile from macOS
msc check --target=raiser tooling/generator/generate.ms   # type-check the generator
MSC=<candidate msc> bash tooling/generator/tests/run.sh   # generator suite (macOS or Windows lane by host)
```

- **The gate before a land**: `msc check src/index.ms`, every file under `test/` and `test/common/` through `msc test`, `msc build examples/helloWebview.ms`, and `msc check --target=raiser tooling/generator/generate.ms`. That last one is the only gate step that compiles the generator: `msc check tooling/generator/cli.ms` stays clean when `generate.ms` breaks, because the CLI only spawns the evaluator that imports it. One `msc` per directory at a time. No `rm -rf out`; switching `--os` needs `-f`, because cached objects are keyed by source path and not by target.
- **A Windows host builds natively**: the same gate commands run as they are; a built `.exe` runs with `WebView2Loader.dll` (from `vendor/webview2/runtime/x64/`) beside it, and `examples/nativeContent.ms` is the by-hand check for native content, a webview child and their input.
- **Linux builds only on a Linux host: WSL Ubuntu with WSLg on the Windows machine**. The `when (linux)` block runs `pkg-config gtk4 webkitgtk-6.0 libnotify ayatana-appindicator-glib libsecret-1` at `@comptime`, and those packages exist only there: install `libgtk-4-dev libwebkitgtk-6.0-dev libayatana-appindicator-glib-dev libnotify-dev libsecret-1-dev`. Call `msc` through the `~/.local/bin/msc` wrapper and never a symlink, because a symlinked `msc` does not find std. Run from `/mnt/c/...` with a login shell (`bash -lc`) so the wrapper is on `PATH`. `ion app … --target linux` also needs `appimagetool` (1.9.1, from its GitHub releases) on that `PATH`.
- A structural change to window, webview or IPC is smoke-tested by hand: build the `.app` with `scripts/make-app.sh`, launch it, and read its stdout for `auto-probe: ipc alive`, `MS command addNumbers(100, 23)` and `[ion] IPC rejected: invalid invoke_key`.

Measured 2026-10-14 on `msc` v0.3.3 (build `9a4775dc`), Windows 11 host: `msc check src/index.ms` and `msc check --target=raiser tooling/generator/generate.ms` clean, the ten test files green, `examples/helloWebview.ms` links `helloWebview.exe`, and `python tooling/generator/tests/cli.py` passes with `MSC` naming `msc.exe`. v0.3.3 wants `msc run` options before the file. Later the same day, on `wt/ion-windows-target`: `msc check cli/main.ms` clean, `msc build cli/main.ms` links, `ion app <exe> … --target windows` stages the payload and stops at the missing `makensis`, and `bash tooling/generator/tests/run.sh` passes its Windows lane. On `wt/ion-cli-msc` (2026-10-16): `ion build` and `ion test` call `msc` (the `MSC` env var, else `msc` on PATH, an error naming it when missing); the built `ion build examples/helloWebview.ms` links `out/release/helloWebview.exe` and `ion test` passes 15 of 15 files. Not run there: macOS, Linux, the macOS generator lanes, the `.app` smoke test.

Measured 2026-10-18 on `msc` v0.3.4 (build `3e645dc4c`), macOS 26.6 host: the gate is green (fifteen test files), and the `.app` smoke test prints its three lines when the bundle carries `--asset=examples/hello.html --asset=examples/ion.js` and `--sign`. Its stdout is block-buffered when not a terminal, so read it through a pty; a bare `out/debug/helloWebview` aborts in `UNUserNotificationCenter` without a bundle. The macOS probes (`examples/*Macos.ms`, `frameStarve`, `loopWake`, `clipboardOnly`, `keychainTest`) print PASS lines and exit 0; results are in `TODO.md`. `contentInputMacos` and `frameStateMacos` activate the app and need to keep the foreground: one run while the machine was in use went red (2 and 3 checks, not captured) and both were green on the two reruns. Not run on macOS: the generator lanes, `audio`, `micPermission`.

## Git

Ion follows the worktree playbook enabled by `~/metascript/CLAUDE.md` and uses `~/nerdtools/claude/tools/wt.sh` with the gate above. Shared session context prints the active card and counts `~/metascript/.inbox/ion/`; read those notes first.

## Boundaries

- Ion stays thin. No capability ACL, isolation iframe, plugin framework or FS scope without the person asking for it.
- Code that needs Neon or Void belongs to Lightcube. Ion hands out a compositor root, webviews and raw input; it does not draw and does not hit-test.
- A capability lands on all three platforms or is recorded as a stub in `TODO.md` the same day; a symbol in `bridge.h` that one platform does not define breaks that platform's link.

## Conventions

- MS files camelCase; MS API camelCase, verb first (`open`, `installTray`); types PascalCase; modifier flags PascalCase (`ModCmd`); module-private state `_`-prefixed.
- C / ObjC bridge functions are `ion`-prefixed camelCase (`ionOpen`, `ionInstallTrayImage`).
- Most `src/*.ms` files are under 100 lines; split one that nears 200.
- New code stores function values directly (`Map<string, Command>`, `arr[i](args)`, inline handlers with an early `return`). `command.ms` and `ipc.ms` still carry parallel arrays and a hoisted `dispatchCall` from a compiler bug that no longer reproduces; collapsing them is open work, proven by ion's own tests.
- Code, README and this file are English.
