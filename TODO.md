# ion — TODO / Recovery notes

State as of 2026-08-03. Rewritten after a full source probe — the previous
version (2026-05-18) had drifted badly from what's actually on disk.

> **How to read this file**: "on disk" means the code exists and is wired into
> the build. It does **not** mean re-verified today. The last recorded
> end-to-end verification for Windows and Linux was in a Parallels VM around
> 2026-05-18/19. Anything marked ⚠️ is a claim in the docs that the source
> contradicts.

## Capability matrix (verified by source inspection)

| Capability | macOS | Windows | Linux | Native impl |
|---|---|---|---|---|
| Window + webview | ✅ | ✅ | ✅ | WKWebView / WebView2 / WebKitGTK |
| IPC + `command()` | ✅ | ✅ | ✅ | `webview/messaging` + `eval` |
| Custom URI scheme (`ion://`, `asset://`) | ✅ | ✅ | ✅ | `webview/protocol.{m,cpp,c}` |
| External-link routing | ✅ | ✅ | ✅ | `common/navpolicy.c` + per-platform nav |
| Tray | ✅ | ✅ | ✅ | NSStatusItem / Shell_NotifyIcon / AppIndicator |
| Notifications | ✅ | ✅ | ✅ | UNUserNotification / balloon / libnotify |
| File dialog | ✅ | ✅ | ✅ | NSOpenPanel / IFileOpenDialog / GtkFileChooser |
| Global hotkey | ✅ | ✅ | ✅ | Carbon / RegisterHotKey / XGrabKey (X11) |
| Content protection | ✅ | ✅ | ✅ | `security/content_protect.*` |
| Keychain / secrets | ✅ | ✅ | ✅ | Keychain / CredWriteW (advapi32) / libsecret |
| `openExternal` | ✅ | ✅ | ✅ | `core/shell.{m,c}` |
| Multi-window | ✅ | ✅ | ✅ | `common/windowRegistry.c` + `windowEvents.c` |
| Native menu bar | ✅ | ❌ | ❌ | `macos/chrome/menu.m` only |
| Render surface | ✅ | ❌ | ❌ | `macos/core/renderSurface.m` only |
| OTA `check` / `download` / verify | ✅ | ✅ | ✅ | pure MS (`src/update.ms`) |
| OTA `apply` (install + relaunch) | ✅ | ⛔ stub | ⛔ stub | `update/install.{m,c}` |

Native LOC: macOS 1715 · Windows 2119 · Linux 1508 · shared C 1392.
MetaScript LOC: 2016 across 20 modules.

## What the old docs got wrong

These are already corrected in `README.md` / `CLAUDE.md` as of this pass, but
recorded here so nobody re-introduces them:

- ⚠️ **"Linux not started"** — Linux is fully wired (1508 LOC, 20 files),
  including keychain via libsecret and the `@comptime pkg-config` flag
  resolution that used to be parked.
- ⚠️ **"Windows: only NSIS packaging pending"** — `scripts/make-app-windows.nsi`
  + `scripts/utils.nsh` exist.
- ⚠️ **"Not a multi-window manager — v0 is single-window"** — `windowManager.ms`
  (227 LOC) exports 25 symbols; `common/windowRegistry.c` backs it on all three
  platforms.
- ⚠️ **"GPU surface deferred indefinitely"** — `renderSurface.ms` (78 LOC) +
  `macos/core/renderSurface.m` shipped, with a 203-line design doc.
- ⚠️ **"OTA not implemented"** — client is real; only the *install* step is
  macOS-only.
- ⚠️ **`command-builder/`** — referenced by README, **does not exist**. The CLI
  now lives at `src/cli/index.ms` (347 LOC) with tests in `src/cli/test/`.
- ⚠️ **`bin/ion`** — referenced by README as the shipped CLI binary; **no `bin/`
  directory on disk**. Every `./bin/ion …` line in the README is currently
  unrunnable.
- ⚠️ **`scripts/build-release.sh`** — referenced by CLAUDE.md; not present.

## Open work

### P0 — Publish readiness (blocks making this a repo)

Done:

1. ~~**`git init`**~~ — done. `origin` → `git@github.com:metascriptlang/ion.git`.
2. ~~**`.gitignore`**~~ — covers `out/`, `*.o`, `web/dist/`, packaged artifacts.
   `vendor/webview2/` is deliberately kept: version pinned at 1.0.2849.39 and the
   Windows build depends on those exact headers.
3. ~~**Strip personal paths**~~ — no `/Users/<user>` references remain.
4. ~~**Fix `build.ms`**~~ — `entry` → `./src/index.ms`; `files` widened to include
   `.c/.h/.m/.cpp/.hpp` + `vendor/webview2` + `scripts` + `assets`, without which
   a published package cannot build. Version still `0.0.1`.
5. ~~**De-brand the source**~~ — no file names the original consumer app. The
   one real defect was `macos/update/install.m`, which hardcoded the consumer's
   name into the osascript admin prompt shown to **every** ion app's users; it
   now derives the app name and destination from `destAppPath`.

Remaining:

6. **Delete stale duplicate** — root `cli/main.ms` (2026-05-15) is superseded by
   `src/cli/index.ms` but still on disk and divergent.
7. **Answer "how does a stranger build this?"** — the build depends on
   `~/metascript/recompiler` being present and containing the fixes listed under
   *Cross-references* below. Without a public/pinned recompiler, a clone is not
   buildable. This is the real gate on going public, not code quality.
8. **`vendor/webview2/runtime/x64/WebView2Loader.dll`** — a prebuilt Microsoft
   binary committed into an MIT repo. Confirm the SDK licence permits
   redistribution, or fetch it at build time instead.

### P1 — Doc truth

- `docs/MULTI-WINDOW.md` drifts from the shipped API: it imports
  `getAllWindows` and `setContentProtected`, but `src/index.ms` exports
  `windowCount` and `setWindowContentProtected`. Reconcile.
- `web/` (607 LOC TS package with its own `package.json` / `tsconfig.json` /
  tests) is undocumented everywhere. Decide whether it ships and describe it.
- `src/update.ms`'s header comment says "Linux + Windows install bridges are not
  implemented yet" — correct, but the same file's `docs/AUTO-UPDATE-SPEC.md`
  reference points outside the repo.

### P2 — Feature gaps

- **OTA install on Windows** — design already noted in
  `platform/windows/update/install.c`: NSIS `.exe` spawned elevated via
  `ShellExecuteEx` + `runas`, or `MOVEFILE_REPLACE_EXISTING` for in-place.
- **OTA install on Linux** — AppImage atomic replace via `rename(2)`; polkit
  `pkexec` only if targeting system paths.
- **Menu bar on Windows / Linux** — macOS-only today.
- **Render surface on Windows / Linux** — macOS-only today. Note that
  `renderSurface` symbols are exported from `src/index.ms` on every platform;
  only dead-code elimination keeps non-macOS builds linking. Calling it on
  Win/Linux is a link error, not a runtime error.
- **Toast WinRT** — current Windows notification is a balloon tip (renders via
  the Toast/Action Center pipeline on Win10/11 anyway). Proper
  `ToastNotificationManager` needs an AUMID from a Start Menu shortcut.

### P3 — Test coverage

9 test files total, all unit-level and all on pure logic:
`test/{jsescape,hotkeyResult,keycodes,mods}.ms`,
`test/common/{invokekey,queue,navpolicy}.ms`,
`src/cli/test/{dispatch,smoke}.ms`.

Nothing exercises the native layer. Every window / webview / IPC / chrome path
is covered only by the manual smoke test in `CLAUDE.md`. Given three platforms
now share `common/` C code, a headless harness for `windowRegistry`,
`protoReg`, and `mime` would pay for itself quickly.

## Cross-references — MS recompiler changes this repo depends on

Build reproducibility requires these in `~/metascript/recompiler/`:

1. **`runtime/` POSIX type fixes** (4 files): `<sys/types.h>` added to
   `fs/posix.c`, `process.h`, `net/socket.h`, `io/engineReadiness.c`. macOS libc
   included them transitively; Linux glibc is strict. Fixes `mode_t`, `pid_t`,
   `ssize_t`.
2. **`osTarget` → `targetOs` always-set refactor** (9 files, ~65 callsites).
   `CliOptions.osTarget`'s `""` ambiguously meant both "native build" and "no
   explicit cross-compile". Now `targetOs: string` always set, defaulting to
   host `platform`; cross-compile is `targetOs !== platform`.
3. **`codegen/c/expressions.ms` `variantStructCName`** — unified variant struct
   C-name lookup to a single typeCache source of truth. Previously two codegen
   passes resolved variant identity by two different keys; the fallback emitted
   a raw interface name unknown to consumer `.c` files, surfacing as
   `error: 'NativeBuild' undeclared` for cross-file discriminated unions.

## Parked

- **Raiser VM stdlib access** — the `@comptime` VM has a hand-maintained host
  table (`src/compiler/meta/hostTable.ms`, ~20 entries) instead of reaching MS
  `std/*` directly. The `pkg-config` use case that motivated it is now unblocked
  (Linux flags resolve correctly), so this is no longer on ion's critical path.
  The auto-scanner sketched at `hostTable.ms:25-36` would retire the bug class
  permanently. Sơn-driven, dedicated recompiler session.
- **Toast WinRT** — see P2.
