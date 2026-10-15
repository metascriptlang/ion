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
| Empty window, compositor root (`windowRoot`, `windowDevice`) | ⛔ unbuilt | ✅ | ⛔ unbuilt | DirectComposition on a D2D device / contentView / GtkFixed |
| Webview as a component (`createWebview`, node, bounds, IPC by label) | ⛔ unbuilt | ✅ | ⛔ unbuilt | WebView2 composition controller per webview / WKWebView / WebKitGTK |
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
| `show` | ✍️ in source (`SDL_*`), not re-measured | ✅ measured 2026-10-15 (`ShowWindow SW_SHOW`) | ✍️ in source (GTK), not re-measured | `core/window.{m,c}`; `examples/windowControls.ms` on Windows |
| `hide` | ✍️ in source (`SDL_*`), not re-measured | ✅ measured 2026-10-15 (`SW_HIDE`) | ✍️ in source (GTK), not re-measured | same |
| `focus` | ✍️ in source (`SDL_*`), not re-measured | ✅ measured 2026-10-15 (`SetForegroundWindow`, Alt-key fallback after winit `window.rs:1832`); a window another app keeps in front cannot be forced | ✍️ in source (GTK), not re-measured | same |
| `minimize` | ✍️ in source (`SDL_*`), not re-measured | ✅ measured 2026-10-15 (`SW_MINIMIZE`) | ✍️ in source (GTK), not re-measured | same |
| `maximize` | ✍️ in source (`SDL_*`), not re-measured | ✅ measured 2026-10-15 (`SW_MAXIMIZE`) | ✍️ in source (GTK), not re-measured | same |
| `setTitle` | ✍️ in source (`SDL_*`), not re-measured | ✅ measured 2026-10-15 (UTF-8 to UTF-16, `é中文` read back) | ✍️ in source (GTK), not re-measured | same |
| `setSize` and `createWindow` size (client area, device-independent pixels) | ✍️ in source (`SDL_*`), not re-measured | ✅ measured 2026-10-15 at 96 dpi: client rect equals the size asked, decorated or not, also from a maximized window. 144 dpi not run: one 96 dpi monitor | ✍️ in source (GTK), not re-measured | `AdjustWindowRectExForDpi` (winit `window_state.rs:507`) |
| `setPosition` (outer frame top-left, virtual-screen pixels) | ✍️ written, uncompiled: frame top-left via `SDL_GetWindowBordersSize` then `SDL_SetWindowPosition(x + left, y + top)` (SDL places the content origin); a failing borders call logs to stderr and does not move | ✅ measured 2026-10-15 (`GetWindowRect` equals the point) | ✍️ in source (`gtk_window_move`, NorthWest gravity places the frame top-left per GTK3 docs), not re-measured | winit `window.rs:560` |
| `setAlwaysOnTop` | ✍️ in source (`SDL_*`), not re-measured | ✅ measured 2026-10-15 (`WS_EX_TOPMOST` set and cleared) | ✍️ in source (GTK), not re-measured | `HWND_TOPMOST` / `HWND_NOTOPMOST` (winit `window_state.rs:405`) |
| `setDecorations` | ✍️ in source (`SDL_*`), not re-measured | ✅ measured 2026-10-15 (`WS_CAPTION` set and cleared; client size and origin unchanged) | ✍️ in source (GTK), not re-measured | `WS_OVERLAPPEDWINDOW` or `WS_POPUP` + `SWP_FRAMECHANGED` |
| Event `focused` / `blurred` | ✍️ `SDL_EVENT_WINDOW_FOCUS_*`, not re-measured | ✅ measured 2026-10-15 (`WM_ACTIVATE`) | ✍️ `notify::is-active`, not re-measured | `common/windowEvents.c` queue, `ionPollEvent` returns 3 |
| Event `resized` / `moved` | ✍️ `SDL_EVENT_WINDOW_RESIZED/MOVED`, not re-measured | ✅ measured 2026-10-15 (`WM_SIZE`, `WM_MOVE`; no `moved` while minimized) | ✍️ `configure-event` and root allocate, not re-measured | same |
| Event `close-requested` | never pushed: `SDL_EVENT_WINDOW_CLOSE_REQUESTED` quits the app (source) | ✅ measured 2026-10-15: pushed from `WM_CLOSE` (title-bar close), then the window is destroyed and the app quits. No veto | never pushed: `delete-event` quits the app (source) | `docs/MULTI-WINDOW.md` lists close interception as open |
| Event `destroyed` | never pushed (source) | ✅ measured 2026-10-15: pushed from `WM_DESTROY` (also for `closeWindow`); the loop delivers it before quitting | never pushed (source) | same |
| Native menu bar | ✅ | ❌ | ❌ | `macos/chrome/menu.m` only |
| Window input records (pointer, key, text, IME, focus, resize, leave) | ⛔ unbuilt | ✅ | ⛔ unbuilt | `windows/input/input.c` / `macos/core/contentHost.m` / `linux/input/input.c` |
| Pointer forwarding into a webview (`forwardPointer`) | n/a | ✅ | n/a | WebView2 `SendMouseInput`; WKWebView and WebKitGTK take OS input themselves |
| Window frame clock (`FrameOnDemand` / `FrameContinuous`) | ⛔ unbuilt | ✅ | ⛔ unbuilt | `common/frameClock.c`; Windows compositor clock in `windows/webview/poll.c` |
| `runLoop` runs msc's loop (`setTimeout`, `await` of a `spawn`, actor messages) | ✍️ written, uncompiled | ✅ measured 2026-10-15 | ✍️ written, uncompiled | `msRunOnce(0)` each turn; Windows `windows/webview/poll.c` waits on msc's next timer and a watcher on msc's IOCP; macOS and Linux pumps already poll every 16 ms |
| `ionWakeLoop` from any thread, `onWake` | ✍️ written, uncompiled | ✅ measured 2026-10-15 | ✍️ written, uncompiled | event in the Win32 wait list / `SDL_PushEvent(SDL_EVENT_USER)` / `GCond` signalled into the 16 ms wait |
| Text clipboard (`readClipboardText`, `writeClipboardText`) | ✍️ written, uncompiled | ✅ measured 2026-10-15 | ✍️ written, uncompiled | `CF_UNICODETEXT` / `NSPasteboard` / `GtkClipboard` |
| IME preedit cursor in UTF-16 units | ✍️ written, uncompiled | ✍️ written, not driven (needs an IME) | ✍️ written, uncompiled | the conversion `ion_utf16_units` is tested (`test/common/utf16.ms`); `GCS_CURSORPOS` and `NSRange` are already UTF-16 |
| Audio file playback (`loadSound`, play, pause, stop, seek, volume, loop, mute, rate, status) | ⛔ unbuilt | ✅ | ⛔ unbuilt | `common/audio.c` on miniaudio `ma_engine`; same C file on all three |
| Audio PCM streams (`openAudioOutput` / `openAudioInput`, ring buffer, underrun counter) | ⛔ unbuilt | ✅ | ⛔ unbuilt | `common/audio.c`: `ma_device` + SPSC `ma_pcm_rb`, C-only device callback |
| Audio recording (`startRecording`, pause, resume, stop, status) | ⛔ unbuilt | ✅ | ⛔ unbuilt | `common/audio.c`: capture `ma_device` into `ma_encoder`, WAV 16-bit only |
| OTA `check` / `download` / verify | ✅ | ✅ | ✅ | pure MS (`src/update.ms`) |
| OTA `apply` (install + relaunch) | ✅ | ⛔ stub | ⛔ stub | `update/install.{m,c}` |

Window text input, measured 2026-10-15 on Windows 11: `examples/textFilter.ms` sends `WM_CHAR` and `WM_SYSCHAR` straight to the window procedure (so `TranslateMessage` is not exercised) and asserts `onText`. Units below 0x20 and DEL produce no text and no key record `text`, `WM_SYSCHAR` (Alt accelerators) produces none, and printable units, surrogate pairs and Ctrl+Alt (AltGr) text still arrive; this matches macOS `isTypedText` and winit `keyboard.rs:232-250`.

Window controls and events, measured 2026-10-15 on a Windows 11 host (one 3440x1440 monitor at 96 dpi): `msc build examples/windowControls.ms`, then run; it reads each control back through Win32 (`GetClientRect`, `GetWindowRect`, style and exstyle bits, `IsWindowVisible`, `IsIconic`, `IsZoomed`, `GetWindowTextW`) and exits 1 on a FAIL. A window another app has pulled the foreground from skips the `blurred` check on minimize.

Loop, wake and clipboard, measured 2026-10-15 on msc v0.3.3 (build `9cf5708c`), Windows 11:
`examples/loopWake.ms` logs the 500 ms `setTimeout` firing 500 ms after start, an `await` of a
`spawn` resuming inside `runLoop`, the clipboard round trip of `é中文`, and a raw `CreateThread`
calling `ionWakeLoop` after 5 s: `onWake` runs and one frame is drawn. Process CPU time over 3 s
idle, before and after the wake: 0 ms and 0 ms (two runs; the clock ticks at 15.6 ms). The macOS
and Linux code was written without a compiler or a machine to run it. The preedit cursor was not
driven by a real IME.

Native LOC: macOS 1715 · Windows 2119 · Linux 1508 · shared C 1392.
MetaScript LOC: 2016 across 20 modules.

Audio, measured 2026-10-15 on a Windows 11 host with `msc` v0.3.3, default devices: `examples/audio.ms` recorded
2 s mono 48 kHz (`out/rec.wav`, 192044 bytes, 96000 frames, nonzero samples, read back with Python `wave`), loaded it
at `durationMs=2000`, seek to 1200 ms landed at 1200, `finished` flipped true once at position 2000, a 440 Hz sine
written from MetaScript as 94 x 1024 frames at 48 kHz gave `underruns=0`, and `x.m4a` returned
`unsupported audio format .m4a`. A probe decoded wav, flac, mp3 and ogg vorbis (ffmpeg-made, 2 s each; duration 2000 ms,
`finished` once). Format set: playback wav, flac, mp3, ogg vorbis (miniaudio decoders + vendored `stb_vorbis`);
recording WAV only; anything else is a named error and m4a/aac has no decoder. `rate` is pitch (speed and pitch move
together). macOS and Linux are written and uncompiled: the same `audio.c` plus `-framework CoreFoundation/CoreAudio/AudioToolbox`
and `-ldl -lpthread -lm` in `src/audio.ms`; neither host was run. Limits: status is polled (`setInterval`
at the app's progress interval, the expo-av model); `audio.c` does not call `ionWakeLoop`, so audio
links without the window host; the recording callback writes the file on the device
thread, so a slow disk drops input; no device enumeration, effects or MetaScript audio callback.

Project generation, measured 2026-09-22: macOS and iOS arm64 development
applications build through Xcode. iOS simulator Debug/Release launch, ad-hoc
signing and unsigned device builds are verified. Android arm64 (measured
2026-09-23): a Gradle project builds Debug and signed Release APK/AAB and runs
the JNI lifecycle fixture on the Android 36 emulator and a physical Seeker phone. A package's Java
reaches that project as an Android library module it declares with `androidLibrary`
(`src/android.ms`; measured 2026-09-25 on the emulator). Neither ports Ion's
runtime APIs or integrates Neon. See
[PROJECT-GENERATOR.md](docs/PROJECT-GENERATOR.md#verification) for the measured
tree, command and remaining boundaries.

Windows desktop application, measured 2026-10-14 on msc v0.3.3 with Build
Tools 2022: a `Target.windowsApp` manifest generates a Visual Studio solution
whose MSBuild Debug and Release builds put the executable, `WebView2Loader.dll`
and the declared assets in `resources/`; `examples/helloWebviewProject.ms`
launched from another directory logs `auto-probe: ipc alive`. With NSIS 3.13,
`ion app <exe> IonHello dev.ion.IonHello --target windows --asset examples/hello.html`
builds `out/IonHello-setup.exe` (463 KB, unsigned). Not measured: running that
installer (per-machine, needs elevation), Visual Studio IDE debugging, an icon
resource.

Windows Android build-host boundary, measured 2026-09-30: unified generation
and the generated NDK tool selection run on Windows. APK construction is
compiler-blocked by the Windows batch-tool invocation recorded in workspace
card `.inbox/compiler/2026-09-20-emcc-spawn-windows.md`; no Android runtime host,
native-load, Release-JNI or lifecycle claim follows from that generation.
Commands and limits are in `docs/PROJECT-GENERATOR.md`, "Windows build-host
boundary". No generated-project workaround is approved.

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
- ⚠️ **`command-builder/`** — referenced by README, **does not exist**. That CLI
  library now lives at `src/cli/index.ms` (347 LOC) with tests in `src/cli/test/`;
  `cli/main.ms` is the `ion` CLI built on it.
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

6. **Answer "how does a stranger build this?"** — the build depends on
   `~/metascript/recompiler` being present and containing the fixes listed under
   *Cross-references* below. Without a public/pinned recompiler, a clone is not
   buildable. This is the real gate on going public, not code quality.
7. **`vendor/webview2/runtime/x64/WebView2Loader.dll`** — a prebuilt Microsoft
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
- **Window content on macOS and Linux (2026-10-15)** — the empty window,
  webview component, input records and per-window frame clock were written to
  the `docs/WINDOW-CONTENT.md` contract on a Windows host and never compiled:
  "unbuilt" in the matrix. Handoff:
  `~/metascript/.inbox/ion/2026-10-15-window-content-mac-linux.md`.
- **Frame clock on macOS** — two debts. Not written: vsync (`CVDisplayLink`),
  and the inactive and minimized pause (`ion_frame_window_state` is never
  called), so a continuous surface ticks at the 16 ms poll rate in every window
  state. Written but never compiled: the frame emission in `macos/webview/poll.m`
  (2026-09-24) and the per-window `ion_frame_window_open` / `close` / `state`
  calls (2026-10-15), both from a Windows host — `main` may not build on macOS
  until a Mac session runs the gate. Handoff: `~/metascript/.inbox/ion/2026-09-24-macos-frame-clock.md`.
- **Frame clock on Windows 10** — not written: `windows/webview/poll.c` has one
  tick source, `DCompositionWaitForCompositorClock`, and without it prints
  `[ion] frame clock: ... not found` and sends no frame. That the entry point is
  missing on Windows 10 is taken from memory, not checked against its docs or on
  a Windows 10 box. `IDXGIOutput::WaitForVBlank` is the candidate second source.
- **Surface fully covered by other windows** — not written: a continuous surface
  keeps ticking while another window hides it. Windows sends no event for that;
  it needs a geometry tracker over every top-level window. A cloaked window does
  stop its frames, measured with an app cloak (`DWMWA_CLOAK`); a shell cloak
  (switching virtual desktop) goes through the same hook but was not exercised.
- **Windows composition hosting** — since WebView2 moved to a
  `CompositionController` (2026-09-23) the host forwards what windowed hosting
  gave for free. Measured 2026-09-23 on WebView2 Runtime 153.0.4234.48: file
  drag and drop from Explorer reaches the page (`webview/host.cpp` drop target →
  `ICoreWebView2CompositionController3`); UI Automation reaches the page's
  Document/Text/Edit under the Ion window, by hosting a UIA element on the
  browser process's top-level `Chrome_WidgetWin_1` popup (an undocumented
  Chromium window, found by class, browser PID and position — recheck on a
  runtime update). Not tried with Narrator/NVDA/JAWS, nor with more than one
  webview. Touch in the webview frame reaches the page as `pointerType`
  "touch" at frame coordinates (`WM_POINTER*` → `SendPointerInput`, measured with
  `InjectTouchInput`, no touch hardware here); outside the frame Windows
  promotes it to mouse input for the surface. Pen measured the same way
  (`InjectSyntheticPointerInput`): the page sees `pointerType` "pen" with its pressure.
- **Touch and pen into a webview on Windows** — reach the page as promoted
  mouse events through the app's forwarding, not as pointer input with
  pressure and contact data (`docs/WINDOW-CONTENT.md`).
- **One window on Windows** — `ionCreateWindow` refuses a second window.
- **Toast WinRT** — current Windows notification is a balloon tip (renders via
  the Toast/Action Center pipeline on Win10/11 anyway). Proper
  `ToastNotificationManager` needs an AUMID from a Start Menu shortcut.
- **Windows native build, measured 2026-09-23** (`msc` v0.2.55, build
  `dcfa743b`, Windows 11 host): `msc check src/index.ms` clean, every file
  under `test/` and `test/common/` green, `helloWebview`, `renderSurfaceSmoke`
  and `surfaceD3D11` build and link. The `ionInput*` accessors now live once in
  `common/inputEvents.c`, which also removes the Linux gap of the same name
  (not built on Linux). `surfaceD3D11` measured: D3D11 clear under a
  transparent webview panel, key/text/focus/resize/pointer events printed,
  typing inside the panel reaches the webview and not the surface, IPC round
  trip (`auto-probe: ipc alive`, `addNumbers(100, 23)`) through the
  composition controller. By hand the same day: a DPI change 96 → 144 → 96
  gives one `resize` each (1328x844 at scale 1.5, back to 884x561); UniKey
  Telex types "tiếng việt" into the webview, and its Backspace + `VK_PACKET`
  output reaches the surface as a Backspace key then `text` (replayed with
  `KEYEVENTF_UNICODE`, a surrogate pair arrives whole). Not measured: an
  IMM32/TSF IME composition (`preedit` events) — no Microsoft IME is
  installed on this box.

Windows behaviour that is not a bug: a 1–2 s white flash on the first launch of
a session (WebView2 process spawn + COM init; a splash screen is the answer),
and the GUI subsystem detaching `stdout`/`stderr` from the launching terminal
(`app.exe > log.txt 2>&1` while debugging).

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
