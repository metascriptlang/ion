# Ion — native desktop runtime for MetaScript

Window, webview, IPC and native chrome (menu, tray, notifications, hotkeys, file dialog, keychain, updater, render surface) behind one API. Not a UI framework: ion has no opinion about how pixels are drawn. Open source, MIT. Neon and Lightcube consume it; ion imports neither.

Workspace rules (toolchain, compiler boundary, arcs and cards) are in `~/metascript/CLAUDE.md` and are not repeated here.

## Where the truth is

| question | file |
|---|---|
| what exists per platform, what is a stub | [`TODO.md`](./TODO.md), the capability matrix; it wins over every other text |
| user-facing API and quick start | [`README.md`](./README.md) |
| custom URI schemes, `file://` block | [`CUSTOM-PROTOCOL.md`](./CUSTOM-PROTOCOL.md) |
| multi-window, render surface, project generator | `docs/MULTI-WINDOW.md`, `docs/RENDER-SURFACE.md`, `docs/PROJECT-GENERATOR.md` |
| architectural precedent | `~/metascript/refs/tauri/` — read patterns, do not copy code |

This file holds no status table. A capability claim is edited in `TODO.md`, after running it.

## Layout

- `src/*.ms` — the public API, one concern per file, re-exported by `src/index.ms`. `src/cli/` is the CLI library, `cli/main.ms` the `ion` CLI, `tooling/generator/` the project generator (`bin/ion-generate`).
- `src/platform/bridge.h` — the one C surface every platform implements. `common/` is plain C built everywhere; `macos/` (`.m`), `windows/` (`.c` + `.cpp`, WebView2 vendored in `vendor/webview2/`), `linux/` (GTK3 + WebKitGTK) mirror each other by concern: `core/ webview/ chrome/ input/ security/ update/`.
- `src/ipc.ms` is the home of every build directive: `@compile` / `@passC` / `@passL` inside `when (macos) { … }`, `when (linux) { … }`, `when (windows) { … }`. A branch not taken is never type-checked. `@platform` no longer exists.
- A relative `-I` in `@passC` resolves against the directory of the module that declares it (`src/`), not against the build directory.

## Commands

```bash
msc check src/index.ms                      # type-check the library
msc test test/mods.ms                       # one unit test file; test/*.ms and test/common/*.ms
msc build examples/helloWebview.ms          # macOS host build
msc build examples/helloWebview.ms --os=windows -f   # cross-compile from macOS
MSC=<candidate msc> bash tooling/generator/tests/run.sh   # generator suite
```

- **The gate before a land**: `msc check src/index.ms`, every file under `test/` and `test/common/` through `msc test`, and `msc build examples/helloWebview.ms`. One `msc` per directory at a time. No `rm -rf out`; switching `--os` needs `-f`, because cached objects are keyed by source path and not by target.
- **A Windows host builds natively**: the same gate commands run as they are; a built `.exe` runs with `WebView2Loader.dll` (from `vendor/webview2/runtime/x64/`) beside it, and `examples/surfaceD3D11.ms` is the by-hand check for the render surface and its input.
- **Linux builds only on a Linux host** (Parallels Ubuntu): the `when (linux)` block runs `pkg-config` for GTK/WebKitGTK at `@comptime`, and those packages do not exist on macOS.
- A structural change to window, webview or IPC is smoke-tested by hand: build the `.app` with `scripts/make-app.sh`, launch it, and read its stdout for `auto-probe: ipc alive`, `MS command addNumbers(100, 23)` and `[ion] IPC rejected: invalid invoke_key`.

Measured 2026-09-20 on `msc` v0.2.55 (build `bce99dbf`): `msc check src/index.ms` clean, the seven test files green, the macOS example builds. Red on that day, each an open ion item in `~/metascript/.inbox/ion/`: the Windows cross-build compiles and then fails to link five `ionInput*` symbols that only `macos/webview/poll.m` defines; `msc check cli/main.ms` reports 4 type errors (`Map.get` results returned as non-null in `src/cli/index.ms`, an un-narrowed `.value` in `cli/main.ms`). Not run: Linux, the generator suite, the `.app` smoke test.

## Git

Ion follows the worktree playbook enabled by `~/metascript/CLAUDE.md` and uses `~/nerdtools/claude/tools/wt.sh` with the gate above. Shared session context prints the active card and counts `~/metascript/.inbox/ion/`; read those notes first.

## Boundaries

- Ion stays thin. No capability ACL, isolation iframe, plugin framework or FS scope without the person asking for it.
- Code that needs Neon or Void belongs to Lightcube. The render surface hands out a native surface and input events; it does not draw.
- A capability lands on all three platforms or is recorded as a stub in `TODO.md` the same day; a symbol in `bridge.h` that one platform does not define breaks that platform's link.

## Conventions

- MS files camelCase; MS API camelCase, verb first (`open`, `installTray`); types PascalCase; modifier flags PascalCase (`ModCmd`); module-private state `_`-prefixed.
- C / ObjC bridge functions are `ion`-prefixed camelCase (`ionOpen`, `ionInstallTrayImage`).
- Most `src/*.ms` files are under 100 lines; split one that nears 200.
- New code stores function values directly (`Map<string, Command>`, `arr[i](args)`, inline handlers with an early `return`). `command.ms` and `ipc.ms` still carry parallel arrays and a hoisted `dispatchCall` from a compiler bug that no longer reproduces; collapsing them is open work, proven by ion's own tests.
- Code, README and this file are English.
