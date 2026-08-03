# Changelog

All notable changes to ion will be documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [Semantic Versioning](https://semver.org/) once we tag a 1.0.

## [Unreleased]

### Phase 4.5 — Custom URI Scheme handler (2026-05-18, **mac + win done**, linux waits on linux foundation)

Replaces `file://` with proper-origin custom schemes (Tauri-style). `file://` URLs have **opaque origin** (`null`) per the Fetch/HTML spec, which silently breaks every modern web platform feature that scopes by origin: `history.pushState` throws SecurityError on WebKit, `localStorage` scoping becomes random across all `file://` URLs, Service Workers can't register, COOP/COEP/SharedArrayBuffer disabled. ion ships the proper primitive instead.

**New schemes:**
- `ion://localhost/<path>` — static file mapping. Auto-registered at `open()` time pointing at `ionResourcePath()` (the `.app`'s `Contents/Resources/` on macOS). Apps can register additional schemes via `registerStaticProtocol(scheme, baseDir)` BEFORE `open()`.
- `asset://localhost/<abs-path>` — scoped disk file load (file-picker results, user-selected media). Allowlist declared via `registerAssetScope(rootPaths)`. Requests outside allowed roots return 403.
- `file://` — **blocked** by `IonNavigationDelegate` with console.warn pointing at this changelog.

**New MS surface (re-exported from `index.ms`):**
- `registerStaticProtocol(scheme: string, baseDir: string): boolean`
- `registerAssetScope(allowedRoots: string[]): boolean`

**New native code:**
- `src/platform/common/mime.{c,h}` — extension → MIME table (.html, .js, .css, .png, .woff2, .wasm, ... 17 types).
- `src/platform/common/protoReg.{c,h}` — cross-platform registry: holds `(scheme, baseDir)` pairs + asset-scope roots. Path semantics: query/fragment stripped, percent-decoded, `..` segments rejected (403), empty path → `/index.html`. Registry freezes at `ionOpen()` so reads from the platform callback (WebKit main thread) are immutable by construction.
- `src/platform/macos/webview/protocol.m` — `WKURLSchemeHandler` impl: `startURLSchemeTask:` → `ionProtoLookup` → `didReceiveResponse:` / `didReceiveData:` / `didFinish`. Auto-installs all registered schemes onto `WKWebViewConfiguration` before webview alloc.
- `src/platform/macos/webview/nav_delegate.m` — extended to handle `ION_NAV_BLOCK`: cancels navigation + logs reason. `src/platform/common/navpolicy.c` `file:` rule changed from `ALLOW` → `BLOCK`.
- `src/platform/macos/core/window.m` `ionOpen` — calls `ionProtoFreeze()` first thing.
- `src/window.ms` `open()` — auto-registers `ion` scheme to `resourcePath()` when called with an `ion://` URL.

**Example migration:**
- `examples/helloWebview.ms` — default URL changed from `file://${cwd()}/examples/hello.html` to `ion://localhost/hello.html`. Smoke test passes: `auto-probe: ipc alive`, `MS command addNumbers(100, 23)`, `MS ← hotkey id=1`, `IPC rejected: invalid invoke_key`.
- `examples/protocolDemo.ms` — NEW. Registers `demo://` → `./examples/demoAssets/`, demonstrates pushState + localStorage + MIME autodetect. Verifies `location.origin === "demo://localhost"` (proper origin, NOT null/opaque).

**Origin gotcha** (document in any ion consumer):
Pages loaded via `<scheme>://localhost/...` get origin `<scheme>://localhost` on macOS. `fetch()` from webview to external HTTPS needs CORS `Access-Control-Allow-Origin` to include this origin. ion's `__ion__.invoke` IPC is unaffected.

**Windows port** (same day, 2026-05-18 PM):
- `src/platform/windows/webview/protocol.cpp` — NEW, hand-rolled `IonEnvOptions` implementing all 8 versions of `ICoreWebView2EnvironmentOptions` (v1–v8 via C++ MI; zig's MinGW lacks `wrl/implements.h` so the SDK's template-based base class is unusable). `IonCustomSchemeReg` COM bag per scheme. `WebResourceRequestedHandler` reads via `ionProtoLookup` + builds `ICoreWebView2WebResourceResponse` through `env->CreateWebResourceResponse` + `SHCreateMemStream`.
- `src/platform/windows/webview/controller.cpp` — `ionBuildEnvOptions()` before `CreateCoreWebView2EnvironmentWithOptions`; env stashed in `WebView2State::env`; `ionAttachResourceHandler` after webview ready.
- `src/platform/windows/webview/nav.cpp` — `file://` BLOCK branch.
- `src/platform/windows/core/window.c` — `ionProtoFreeze()` at `ionOpen`.
- `src/ipc.ms` — `@compile` for `protocol.cpp` + `@passL("-lshlwapi")` (`SHCreateMemStream`).
- `std/process/errors.ms` (recompiler-side) — `ProcessError` fields renamed `stdout`→`output`, `stderr`→`errorOutput` to dodge Win `<stdio.h>` macro collision.

**Win runtime verified in Parallels VM**: `ion://localhost/hello.html` loads, `WebResourceRequested` fires, `auto-probe: ipc alive`, `MS command addNumbers(100, 23)`. Smoke test pass.

**Critical landmines documented** (see CUSTOM-PROTOCOL.md "Critical landmines"):
1. `get_TargetCompatibleBrowserVersion` MUST return non-empty SDK version string (`L"130.0.2849.39"` for SDK 1.0.2849.39). Empty `""` → `CreateCoreWebView2EnvironmentWithOptions → E_INVALIDARG`. This was the entire blocker for Win Phase H — discovered via stderr-wrap zig diagnostic.
2. WebView2 QIs v1–v8 (newer versions return `E_NOINTERFACE` gracefully). Hand-roll MI with all versions.
3. String getters MUST return `CoTaskMemAlloc`'d strings (never `nullptr`, never stack-allocated).

**Linux remains deferred** to the Linux foundation epic. The webkit_web_context_register_uri_scheme + webkit_uri_scheme_request_finish pattern is documented in CUSTOM-PROTOCOL.md "Linux" section.

**Recompiler @comptime bugs fixed same day** (separate session): `msStringTrim` registered in Raiser host table + `@comptime` evaluation no longer crashes in large module graphs. Linux GTK pkg-config blocks in `src/ipc.ms` restored with the hoisted-const pattern (`const gtkCflags = @comptime { ... }; @passC(gtkCflags);` — cleaner than inline `@passC(@comptime { ... })`). Linux Phase 2-5 (WebKitGTK, chrome, X11, AppImage) unblocked.

### Cross-platform deep link unification (2026-05-13)

Closes the last v0 gap on Windows: end-to-end deep link routing with single-instance enforcement, behaviorally identical to macOS. Both platforms now emit the same `"deeplink"` IPC contract — MS-side `listen()` handlers don't need platform branching.

**Windows native (NEW):**
- `core/lifecycle.c` `ionInit`:
  - Parses `GetCommandLineW` / `CommandLineToArgvW` for the first URL-shaped arg (containing `://`); stashes in `s_coldStartUrl`.
  - Acquires per-exe named mutex `Local\Ion-SingleInstance-<exe-basename>`. On `ERROR_ALREADY_EXISTS`, finds the primary HWND via `FindWindowW("IonMainWindow")`, sends `WM_COPYDATA` with the URL (custom `dwData = 'IOND'`), raises the existing window, and `ExitProcess(0)`s.
- `core/window.c` ionWndProc:
  - `WM_COPYDATA` handler validates the `'IOND'` marker, enqueues the payload as `"deeplink"` IPC, raises the window.
  - `ionOpen` end-of-call replays any pending `s_coldStartUrl` as `"deeplink"` IPC, then clears it. Matches mac's NSAppleEventManager queue-then-drain pattern.

**MS-side (cross-platform):**
- `examples/helloWebview.ms` distinguishes webview-loadable URLs (`http://`, `https://`, `file://`, `data:`) from custom-scheme deep links. The former override the default URL; the latter are skipped (native dispatches via the `"deeplink"` IPC, webview loads the normal app shell).
- `listen((name) => if name === "deeplink")` handler now fires `notify("Deep link received", url)` for visual confirmation.

**Verification:**
- Windows: `myapp://cube/test-cold` from a non-running state → app installs / launches / balloon fires; with app running, `myapp://cube/test-warm` raises the existing window + balloon (no second instance); double-clicking the installed `.exe` again raises the existing window (no URL).
- macOS: `open -a MyApp.app "myapp://cube/test"` → notification "Deep link received" appears, window raises. End-to-end verified.
- Single-instance on macOS is automatic via `LSGetApplicationForURL` — no code path on our side.

**Architecture note:** Mac and Windows native implementations diverge by necessity (NSAppleEventManager vs `WM_COPYDATA` + mutex) but produce identical IPC contracts. The MS-side handler is unchanged across platforms. Same pattern as ion's other native chrome modules (tray, notify, dialog).

**Bug fix (`scripts/make-app.sh`):** `OUT_DIR="${4:-...}"` would happily absorb a flag like `--url-scheme=…` as the 4th positional, breaking downstream `rm/cp` paths. Now guarded: only takes `$4` if it doesn't start with `--`.

### Windows Phase 4 — global hotkey (2026-05-12)

Closes the last v0 capability gap. Windows now matches macOS for every runtime feature; only packaging (Phase 5) remains.

- **`input/hotkey.c`** wires `RegisterHotKey` / `UnregisterHotKey` against the main HWND. `WM_HOTKEY` arrives on `ionWndProc` (core/window.c) → enqueue `"hotkey"` IPC with payload = id (decimal string), matching mac's Carbon `RegisterEventHotKey` contract.
- **Modifier mapping** (ion bitmask → Win32 `MOD_*`):
  - `1` (Cmd) → `MOD_WIN` — physical-key parity (Mac ⌘ sits where Win key is on a Windows keyboard)
  - `2` (Shift) → `MOD_SHIFT`
  - `4` (Alt) → `MOD_ALT`
  - `8` (Ctrl) → `MOD_CONTROL`
  - Apps wanting "Ctrl on Windows / Cmd on Mac" semantics should branch on `platform` in MS (the pattern already established by `keyCodeFromName`'s per-platform tables).
- **Slot table** fixed at 16 entries (parity with mac, no protocol reason). Returns: `1` success, `0` slots full, `-1` OS refused (combo taken).
- **`hotkey.ms`'s Win32 VK table** (added pre-Phase-2 during solidification) is now actually exercised — `registerHotkeyKey(ModCmd | ModShift, "L", 1)` resolves to `MOD_WIN | MOD_SHIFT + VK_L (0x4C)` via the per-platform dispatch in `keyCodeFromName`.

### Windows Phase 3 — native chrome (tray + notify + dialog) (2026-05-12)

Closes the 3 native chrome stubs that Phase 1 left behind. Windows now sits at full v0 parity with macOS except for global hotkey (Phase 4) and packaging (Phase 5).

- **Tray icon** (`chrome/tray.c`): `Shell_NotifyIconW` with the main HWND as the callback target. `ionInstallTray(title)` uses IDI_APPLICATION + tooltip; `ionInstallTrayImage(pngPath)` loads via `LoadImageW` with two-tier fallback (literal path → `<exe-dir>/resources/<basename>` via `ionResourcePath()` → IDI_APPLICATION). Click left-button → enqueue `tray.click` + raise main window, mirroring mac's `NSStatusItem` contract.
- **Notifications** (`chrome/notify.c`): hidden `Shell_NotifyIcon` entry (`NIS_HIDDEN` state — no extra tray icon visible) with `NIM_MODIFY` + `NIF_INFO` to surface the balloon. Windows 10/11 renders these through the Toast / Action Center pipeline, so users see modern UI even though we use the legacy API. Last-emitted `id` is stored in a static buffer and replayed as the `notification.click` payload on `NIN_BALLOONUSERCLICK` (mac WKWebView delivers the identifier via `UNNotificationResponse.notification.request.identifier`; we mirror by stashing on emit, replaying on click).
- **File dialog** (`chrome/dialog.c`): `IFileOpenDialog` (COM via `COBJMACROS` C-style vtable calls). Modal `Show(hWnd)` blocks the message pump like mac's `NSOpenPanel runModal`. Single-file, no type filter — match mac v0. Returns UTF-8 path string or `""` on user cancel; result cached in a static buffer until the next call.
- **Callback routing**: All `Shell_NotifyIcon` callbacks target the main HWND, not separate `HWND_MESSAGE` windows. The latter don't reliably receive these on Windows 10/11 (`NIN_BALLOONUSERCLICK` was silently dropped in early prototype). `ionWndProc` in `core/window.c` dispatches `WM_APP+1` / `WM_APP+2` to `ionTrayHandleCallback` / `ionNotifyHandleCallback` exposed from the chrome modules via `internal.h`.
- **`run.bat`** (tooling): updated to invoke `helloWebview.exe > ion.log 2>&1` directly instead of `start /WAIT`. `start` detaches stdio from the cmd parent, breaking redirects — Win32 cold-test gotcha worth documenting.

Verified end-to-end in Parallels VM:
- Tray icon visible bottom-right, hover tooltip shows
- Tray left-click → page log `MS ← tray clicked` (via console.log relay through stdout to `ion.log`)
- Auto-launch balloon "Ion ready" appears; ping/pong roundtrip also fires per-ping balloon
- Balloon click → `notification.click` IPC with `id` payload (`demo-launch`, `demo-ping`)

### Windows Phase 2 security parity (2026-05-12)

Closed two security gaps that Phase 2 should have shipped with — mac side has had these since v0, Windows was relying on WebView2 defaults that don't match:

- **DevTools env-gating** — WebView2 default is `AreDevToolsEnabled=TRUE`. Now explicitly disabled in `controller.cpp` after `get_CoreWebView2`, unless `ION_DEVTOOLS=1` (or `true` / `yes` / `on`) is set. Mirrors mac's `WKPreferences.developerExtrasEnabled` env-gate.
- **`forMainFrameOnly` equivalent** — WebView2's `AddScriptToExecuteOnDocumentCreated` has no per-frame flag; the same JS gets injected into every frame (main + iframes). Added a `if (window.self !== window.top) return;` guard at the top of the bootstrap IIFE in `common/bootstrap.c`. `window.__ion__` is now never defined inside iframes regardless of platform. macOS still uses `forMainFrameOnly:YES` on the WKUserScript so the script never reaches iframes there; the JS guard is redundant on mac but harmless and keeps the shared template uniform.

### Windows Phase 2 — WebView2 fully wired (2026-05-12)

Windows port reaches functional parity with macOS for the v0 use case: window + webview + bidirectional IPC + Tauri-style commands + console relay + external-link routing. Verified end-to-end in a Windows 11 Parallels VM — full IPC roundtrip (`ping → pong` + `await ion.call("addNumbers", {a:3, b:5}) → 8`), `localStorage` persistence, content-protection toggle all working.

- **WebView2 SDK vendored** at `vendor/webview2/` — version pinned `1.0.2849.39` from NuGet. Two headers (`WebView2.h`, `WebView2EnvironmentOptions.h`) + the 162 KB `WebView2Loader.dll` for runtime. Loaded dynamically via `LoadLibraryW` (no MSVC `.lib` link — keeps the MinGW/zig cross-compile path clean). Vendored stub `EventToken.h` plugs a MinGW-w64 gap that prevents direct `<WebView2.h>` inclusion.
- **Hand-rolled IUnknown callback classes** instead of `Microsoft::WRL::Callback<>` (MinGW's `wrl/event.h` ships incomplete). Five COM event handlers — env-created, controller-created, add-script-completed, navigation-starting, web-message-received — each ~20 lines of QueryInterface + AddRef/Release + Invoke. Uniform shape; `wrl/client.h` `ComPtr` works fine for ref-counted state.
- **`platform/common/bootstrap.{h,c}`** — shared JS bootstrap template (define `window.__ion__` + invoke_key closure + console relay + error forwarders). Only ONE thing differs per platform: the one-line `nativePost(envelope)` body (mac WKWebView vs Windows WebView2). `ion_build_bootstrap_js(invokeKey, transportBody)` renders the final JS via `snprintf`. Mac `webview/bootstrap.m` migrated to consume the helper — net shrink ~40 lines.
- **`platform/common/json_extract.{h,c}`** — minimal JSON string-field extractor (`ion_json_extract_string(json, key)`). Handles `\"`, `\\`, `\/`, `\n`, `\t`, `\r`. Used by Windows `messaging.cpp` to extract `__key` + `name` + `payload` from WebView2's JSON envelope before invoke_key gating + enqueue. macOS doesn't need it (WKWebView auto-converts JS object → NSDictionary). Pre-extracted to common/ so the planned Linux WebKitGTK port doesn't re-roll the same parser.
- **`platform/windows/webview/` — five focused files** mirroring macOS' subsystem split, each <300 lines:
  ```
  webview/
  ├── internal.hpp     # opaque WebView2State struct (ComPtr<Controller> + ComPtr<WebView> + event tokens)
  ├── controller.cpp   # async init chain: CreateEnvironment → CreateController → bootstrap inject → handlers → Navigate
  ├── eval.cpp         # ionEvalJS via ExecuteScript (extern "C")
  ├── nav.cpp          # NavigationStarting → navpolicy → ShellExecuteW external-link route
  ├── messaging.cpp    # WebMessageReceived → invoke_key verify → ionEnqueueMessage
  └── poll.c           # Win32 PeekMessage pump + IPC queue drain (unchanged from Phase 1)
  ```
- **`platform/windows/state.h`** carries an opaque `void *s_webview2State` so C-side window/lifecycle code can hold the COM state without C++ types leaking into C headers. C++ side casts via `ionGetWebView2State()`.
- **`platform/windows/core/window.c`** — `ionOpen` calls `ionWebView2Start(hwnd, url)` after `CreateWindowExW`, kicks off async init. `WM_SIZE` calls `ionWebView2Resize` to keep the webview flush with the host window. `WM_DESTROY` calls `ionWebView2Shutdown` to release ComPtrs + detach event handlers.
- **Recompiler C++ support added** (`~/metascript/recompiler/src/compiler/cc.ms`) — `@compile("foo.cpp")` (or `.cxx` / `.cc` / `.c++` / `.cp` / `.C` / `.CPP`) now compiles with `zig c++ -std=c++17`. Any C++ source in the build flips a sticky flag that switches the final link step to the C++ driver so `libc++` / `libstdc++` is pulled automatically. Mirrors Nim's `optMixedMode` pattern (`extccomp.nim:591`). Cross-compile inherits — `--os=windows` with C++ sources produces a self-contained `.exe` with libc++ statically linked. Also fixed a cache-restore-path bug: detection now happens in `processCompileDirectives` main-thread loop at directive-resolution time (was inside `compileCFile`, which the global content-addressed cache restore path bypasses).
- **All ion C headers** got `extern "C"` wrappers (`platform/common/*.h`, `platform/windows/*.h`, `platform/bridge.h`) so C++ callers find unmangled C symbols.
- **`hotkey.ms`** keycode table split per-platform (`keyCodeFromNameMacOS` returns Carbon vk; `keyCodeFromNameWindows` returns Win32 VK_*; public `keyCodeFromName` dispatches by runtime `platform`). Resolves the v0 silent-bug where `registerHotkeyKey(ModCmd | ModShift, "L", id)` would have produced the wrong physical key on Windows.
- **`bridge.h`** documents the IPC message contract (table at the bottom listing `tray.click`, `notification.click`, `hotkey`, `deeplink`, `console.*` with payload shapes + emit sites) — gives Phase 3 / 4 native implementers a source of truth.

What's still pending for Windows:
- **Phase 3** — tray (Shell_NotifyIcon + hidden message-only window for click routing), notifications (Toast WinRT + AUMID from NSIS-installed Start Menu shortcut), file dialog (IFileOpenDialog COM). Phase 1 stubs return user-cancel sentinels.
- **Phase 4** — global hotkey via `RegisterHotKey`. Phase 1 stub returns -1.
- **Phase 5** — NSIS installer (`ion app --target=windows`) + Start Menu shortcut + WebView2 Runtime install check.

Known Windows-specific behaviors:
- **Cold-start visual:** ~1-2 s white flash on first launch in a Windows session (Edge process spawn + COM init). Standard WebView2 behavior, not ion-specific. Defer mitigation to a real cross-platform splash screen (covers mobile launch screen too) rather than a Windows-only hide-until-ready hack.
- **GUI subsystem (`-Wl,--subsystem,windows`)** — no terminal pops up next to the `.exe`, but `stdout` / `stderr` are detached by default. For dev debugging, redirect at launch (`helloWebview.exe > log.txt 2>&1`) or wait for a later phase to wire `AllocConsole` behind `ION_CONSOLE=1`.

### Pre-Phase-2 solidification: cross-platform parity (2026-05-12)

Audit pass before wiring WebView2 on Windows. Closed the two real cross-cutting asymmetries between mac and windows code paths so Phase 2 starts from a solid base.

- **`hotkey.ms` keycode table is now platform-aware.** The `keyCodeFromName()` function used to return macOS Carbon virtual key codes only — calling `registerHotkeyKey(ModCmd | ModShift, "L", 1)` on a Windows .exe would have produced the wrong physical-key binding when Phase 4 lands. Now dispatches at runtime via `platform` from `std/process`: macOS → Carbon `kVK_ANSI_*`, Windows → Win32 `VK_*`. Two private helpers (`keyCodeFromNameMacOS` + `keyCodeFromNameWindows`) keep the tables isolated and readable.
- **IPC message contract documented in `bridge.h`.** Native platform code emits IPC messages (`tray.click`, `notification.click`, `hotkey`, `deeplink`, `console.*`) that MS-side `listen()` handlers pattern-match on. The name+payload shape was implicit-from-mac-impl only — Phase 3 / 4 native implementers had no source of truth. Now codified as a table at the bottom of `bridge.h`. Porting a new OS means matching this table, not inventing one.

### Windows Phase 1 — cross-compile pipeline + bare Win32 window (2026-05-11)

First slice of the Windows port. Cross-compiles from macOS via `zig cc` (already on the box, no extra installs) into a runnable `.exe` that opens a bare HWND. Foundation for Phase 2 (WebView2 wiring); white window is intentional — no page content until WebView2 lands.

- **`@platform("...") { ... }` directive** added to MS recompiler. Block-form conditional gate for `@compile` / `@passC` / `@passL`. Filters at `collectDirectives` time so a cross-compile pulls only the matching platform's source files; mac directives don't leak into a Windows build and vice versa. `osTarget` is now threaded through `loadAndCheckGraph` → `checkModuleGraph` so the target is known before directive collection runs. Decorator reference: `@platform` section in `metascript-llms-full.txt`.
- **`bridge.h` promoted** from `platform/macos/bridge.h` → `platform/bridge.h`. Single cross-platform public C contract. Pure C signatures — no Cocoa or Win32 types in the public surface so MS-side imports stay portable. All 8 MS-side imports and 9 mac `.m` files updated for the new path. Doc comments rewritten to cross-platform language (no more SDL+Cocoa-specific phrasing).
- **`platform/windows/` skeleton**:
  ```
  src/platform/windows/
  ├── internal.h               # forward decls + windows.h + WIN32_LEAN_AND_MEAN
  ├── state.h / state.c        # HWND + HINSTANCE globals + ionEnqueueMessage shim
  ├── utf8.h / utf8.c          # shared UTF-8 ↔ UTF-16 conversion helpers
  ├── core/
  │   ├── lifecycle.c          # ionInit / ionQuit
  │   └── window.c             # ionOpen / ionClose / ionResourcePath
  ├── webview/
  │   └── poll.c               # PeekMessageW pump + queue drain; ionEvalJS stub
  ├── chrome/
  │   ├── tray.c               # stubs (Phase 3 → Shell_NotifyIcon)
  │   ├── notify.c             # stub (Phase 3 → Toast WinRT)
  │   └── dialog.c             # stub (Phase 3 → IFileOpenDialog)
  ├── input/
  │   └── hotkey.c             # stub (Phase 4 → RegisterHotKey)
  └── security/
      └── content_protect.c    # SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE)
  ```
- **`@platform("windows") { ... }` block** in `src/ipc.ms` lists the 10 Windows `.c` files + Win32 link libs (`user32`, `gdi32`, `ole32`, `shell32`, `bcrypt`, `uuid`) + `-Wl,--subsystem,windows` (suppresses the default console terminal that pops up next to GUI `.exe`s).
- **WndProc**: WM_CLOSE → DestroyWindow → WM_DESTROY → PostQuitMessage. Closes cleanly without spawning a second window (fixed by removing the redundant top-level `main();` call in `examples/helloWebview.ms` — msc's auto `main_()` call already runs main).
- **`ionResourcePath` convention** on Windows: `<exe-dir>/resources/`, parallels mac's `Contents/Resources/`. Returns `""` in dev mode when no `resources/` dir exists next to the binary.
- **Verified**: `bun ~/metascript/recompiler/bun/run.ts build examples/helloWebview.ms --os=windows --force` → 9.9 MB `helloWebview.exe`, opens window in Parallels VM, closes cleanly, no terminal popup. Mac builds + `.app` bundle unaffected (regression-tested).

What's still stubbed for Windows (deferred phases):
- **Phase 2** — WebView2 (Controller async init + bootstrap script injection + WebMessageReceived → ion_queue + ExecuteScript → ionEvalJS + NavigationStarting → ion_nav_decide).
- **Phase 3** — tray (Shell_NotifyIcon + hidden message-only window), notify (Toast WinRT + AUMID), dialog (IFileOpenDialog COM).
- **Phase 4** — global hotkey via `RegisterHotKey`.
- **Phase 5** — NSIS installer (`ion app --target=windows`) + Start Menu shortcut (AUMID source).

### `@metascriptlang/ion` npm package + bootstrap split (2026-05-10)

Web bundles now consume ion's IPC via a typed npm package instead of an injected `window.ion` global.

- New `web/` workspace contains `@metascriptlang/ion` — TypeScript source, builds to ESM + `.d.ts` via `tsc`. Public API: `call<T>(name, args)`, `invoke(name, payload)`, `on(name, handler)`, `off(name)`.
- Native bootstrap trimmed to **transport only** — exposes `window.__ion__` (closure-scoped invoke_key + post + setReceiver + _dispatch) plus the auto console-relay. Promise routing + handler registry moved to the npm package.
- WKWebView now allows `import './foo.js'` from sibling file:// URLs (`allowFileAccessFromFileURLs` + `allowUniversalAccessFromFileURLs`). Required for bundled HTML to consume the npm package via static ESM imports.
- Demo `examples/hello.html` rewritten as `<script type="module">` importing from `./ion.js` (built dist co-located in Resources/).
- All MS-side `ionEvalJS` calls updated from `window.ion._dispatch` → `window.__ion__._dispatch`.

### Quality bumps (2026-05-10)

Code quality lifted from 6.5/10 to ~8.5/10 before Windows port:

- **30 native unit tests** in `test/common/` covering security-critical pure C: `invokekey` (8 tests — gen, verify, NULL/empty/wrong key rejection), `navpolicy` (14 tests — every rule branch, case-insensitive, defensive), `queue` (9 tests — FIFO, interleaved push/pop, large payload, allocation success).
- **Fail-secure error returns** on security primitives: `ion_random_bytes` returns int (0/-1); `ion_invoke_key` aborts on RNG failure (catastrophic); `ion_queue_push` returns int + logs on `malloc`/`strdup` failure (non-critical, drops message).
- **`internal.h`** consolidates platform-internal forward declarations (`ionInstallURLHandler`, `ionEnsureMenu`, `ionSetupWebview`). `bridge.h` stays public C API only.
- **81 unit tests** total (37 MS + 30 native + 14 command-builder), all passing.

### Platform layer modular refactor (2026-05-10)

Split `src/platform/macos/bridge.m` (639-line monolith) into 14 focused `.m` files mirroring the MS-side organization. Sets the template Linux/Windows ports will follow.

```
src/platform/macos/
├── bridge.h                  # public C interface (unchanged)
├── state.h                   # extern shared globals
├── state.m                   # storage + msg queue + invoke_key gen
├── core/
│   ├── lifecycle.m           # ionInit / ionQuit
│   └── window.m              # ionOpen / ionClose / ionResourcePath
├── webview/
│   ├── bootstrap.m           # WKWebView setup + IonMessageHandler + JS bootstrap
│   ├── nav_delegate.m        # IonNavigationDelegate (external links → browser)
│   ├── eval.m                # ionEvalJS
│   └── poll.m                # ionPollEvent + queue drain
├── ipc/
│   └── url_scheme.m          # IonURLHandler (deep link)
├── chrome/
│   ├── menu.m                # NSMenu + IonMenuTarget
│   ├── tray.m                # NSStatusItem + IonTrayTarget
│   ├── notify.m              # UNUserNotificationCenter + IonNotifDelegate
│   └── dialog.m              # NSOpenPanel
├── input/
│   └── hotkey.m              # Carbon RegisterEventHotKey
└── security/
    └── content_protect.m     # NSWindow.sharingType
```

- Each file 10-146 LOC (was 639 monolith)
- Shared globals in `state.h`/`state.m`; helpers `ionEnqueueMessage` + `ionEnsureInvokeKey`
- Build directives in `src/ipc.ms` list all 14 `.m` paths (recompiler dedupes by path)
- Verified: all 51 unit tests pass + smoke pipeline (IPC, command, hotkey, invoke_key gate, deep link) intact

### `ion` CLI in MetaScript (2026-05-10)

- **`bin/ion`** — single-binary CLI replaces the 4 individual bash scripts (`build-release.sh`, `make-dmg.sh`, `notarize.sh`, `test.sh` deleted; `make-app.sh` retained as implementation of `ion app`). Subcommands: `build`, `app`, `dmg`, `notarize`, `test`. Per-command `--help`. ~207 KB stripped binary.
- **`command-builder/`** — cac-inspired CLI builder library written in MetaScript. Fluent API (`cli().command().option().action()`), positional args (`<required>` / `[optional]`), boolean flags, string options, repeatable options, auto `--help` / `--version`. **14 unit tests** (8 smoke + 6 dispatch).
- **`cli/main.ms`** — ion CLI implementation on top of command-builder. Pure MS for build/dmg/notarize/test; `app` subcommand currently shells out to `scripts/make-app.sh` (port to MS deferred — needs subprocess output capture for `otool` parsing).

### MS compiler bugs uncovered while building the CLI

Documented in `the MetaScript compiler bug tracker` (#8, #9, #10), each with verified minimal repro at `/tmp/ms-bugs/probe*.ms` and workaround active in `command-builder/index.ms`:

- **Bug 8** — class method default parameter values not applied at call site (standalone fn defaults work).
- **Bug 9** — class method passing `string[]` to standalone fn → stray `&` in C codegen.
- **Bug 10** — closure capturing `let` inside `test "…" { }` block → undeclared `_envN_`.

### Codebase solidification (2026-05-09 session)

- **Removed dead stub files** — `src/window.ms`, `src/webview.ms`, `src/gpuSurface.ms` (127 lines from original design, not imported anywhere). Public surface now matches actual implementation.
- **Split `src/index.ms`** (~250 lines monolith) into 9 focused modules: `window`, `ipc`, `command`, `dialog`, `security`, `tray`, `notify`, `hotkey`, `mods`, plus `internal/cstr` and `internal/jsEscape`. Each file <100 lines. `index.ms` is a pure re-export hub.
- **Added README, CLAUDE.md (rewritten), CHANGELOG, MIT LICENSE.**
- **MS-side unit tests** in `test/`: 37 tests across `mods`, `jsescape`, `keycodes`, `hotkeyResult`. Run via `./scripts/test.sh`.
- **Structured hotkey error model**: `HotkeyResult` enum (`Ok`/`UnknownKey`/`SlotsFull`/`Conflict`) + `tryRegisterHotkey*` variants returning the enum. Bridge return code now distinguishes slot-full (0) from Carbon failure (-1). `registerHotkey*` boolean shorthand kept for callers that don't care.

### Documented build directive quirk

MS recompiler drops `@compile`/`@passC`/`@passL` from re-export-only files. Workaround: directives live in `src/ipc.ms` (canonical bridge consumer) so they always survive in the build graph. See CLAUDE.md.

## [0.0.1] — 2026-05-09

Initial release. macOS arm64 only. Single-window webview shell built for MyApp as the primary consumer.

### Added — Core runtime

- **Window + webview** via SDL3 + WKWebView. `open(title, w, h, url)` accepts `file://`, `http(s)://`, `data:` URLs.
- **Bidirectional IPC**:
  - Low-level event channel: `listen((name, payload) => …)`, `invoke(name, payload)`, `eval(js)`.
  - Tauri-style request/response: `command(name, fn)` MS-side / `await window.ion.call(name, args)` JS-side, with auto-stringify args + auto-parse return.
- **Blocking event loop** via `runLoop()` driving `SDL_WaitEventTimeout(16ms)`, pumps Cocoa run loop while idle.

### Added — Native chrome

- **Menu bar** (App / File / Edit / View / Window) with standard accelerators (Cmd+Q/W/R, copy/paste).
- **Tray icon**: text label (`installTray("L")`) or template PNG (`installTrayImage("tray-icon.png")`); click → `tray.click` IPC + window forward.
- **OS notifications** via UNUserNotificationCenter; click → `notification.click` IPC with id payload + window forward.
- **Global hotkey** via Carbon `RegisterEventHotKey` (system-wide, no Accessibility permission needed). Both raw keycode (`registerHotkey`) and key-name (`registerHotkeyKey(mods, "L", id)`) APIs.
- **File dialog** via `NSOpenPanel`: `openFile()` returns selected path or `""`.
- **Deep link** URL scheme handler via `NSAppleEventManager`. Cold-start URLs survive (sit in queue until our handler installs after `SDL_Init`). Runtime URLs route as `deeplink` IPC message.

### Added — Security & hardening

- **invoke_key gate**: 32-byte random hex generated per launch, baked into bootstrap closure (not on `window`), required on every JS→MS message. Raw `webkit.messageHandlers.ion.postMessage(...)` without the key is rejected.
- **`forMainFrameOnly: YES`** for the bootstrap injection — iframes don't get `window.ion`.
- **DevTools env-gated**: off by default; `ION_DEVTOOLS=1` enables.
- **WKNavigationDelegate**: cross-origin user-clicked navigation routed to default browser via `NSWorkspace`, never loaded into the webview.
- **Persistent webview store** (`WKWebsiteDataStore.defaultDataStore`) — cookies, localStorage, IndexedDB survive restarts.
- **Content protection** (`setContentProtected(true)`) — sets `NSWindow.sharingType = NSWindowSharingNone`; screen capture shows black.
- **Hardened Runtime support** in `make-app.sh --hardened`.

### Added — Packaging pipeline

- **`scripts/build-release.sh`**: `bun build --release --strip` wrapper. Output: ~247 KB stripped binary.
- **`scripts/make-app.sh`**: binary → `.app` bundle. Flags: `--icon`, `--asset` (multiple), `--url-scheme`, `--sign[=identity]`, `--hardened`, `--entitlements=path`. Auto-detects non-system dylibs via `otool`, copies to `Contents/Frameworks/`, rewrites install_name + rpath, re-signs.
- **`scripts/make-dmg.sh`**: `.app` → `.dmg` with `/Applications` symlink for drag-install. Output: ~1.2 MB UDZO compressed.
- **`scripts/notarize.sh`**: `xcrun notarytool submit + wait + stapler staple` wrapper.

### Added — Developer experience

- **Console relay**: `console.log/warn/error/info` + `window.onerror` + `unhandledrejection` from the webview pipe back to MS stdout as `[webview log] …`.
- **Bundle resource path**: `resourcePath()` returns `Contents/Resources/` for bundled apps, `""` for dev. Used to construct file:// URLs for shipped HTML.
- **Tray image fallback**: `ionInstallTrayImage(name)` tries the literal path, then falls back to `NSBundle.mainBundle.pathForResource(basename)` — same call works in dev (cwd-relative) and bundled (Resources-relative).

### Documented

- README, CLAUDE.md (working agreement), this CHANGELOG, MIT LICENSE.
- MS Bug 5 workarounds (parallel arrays, pre-extract function values, standalone helper for early-return) documented inline at parked sites.

### Known limitations

- macOS arm64 only. Linux + Windows ports estimated ~1.5-2x macOS effort each, deferred until real demand.
- No automated test suite. Manual smoke test documented in CLAUDE.md.
- No structured error model — most failures return bare boolean; see Solidify-7 in roadmap.
- Hardened Runtime + ad-hoc sign requires `disable-library-validation` entitlement (provided in `assets/app.entitlements`). Real Developer ID sign + bundled same-identity dylibs would let this be removed.
