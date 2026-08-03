# ion — Custom URI Scheme Handler

> **Status (2026-05-18):** macOS done + verified end-to-end via `examples/protocolDemo.ms` (origin `demo://localhost` confirmed) + `examples/helloWebview.ms` migrated and smoke-tested as bundled `.app`. **Windows done same day** — verified in Parallels VM: `ion://localhost/hello.html` loads, `WebResourceRequested` fires, `auto-probe: ipc alive` + `MS command addNumbers(100, 23)` logged. Linux still pending (Linux runtime foundation hasn't started).

## TL;DR

ion ships **Tauri-style custom URI schemes** to replace `file://` for webview asset loading:

- `ion://localhost/...` — app UI assets, mapped from a registered baseDir (the "load my SPA" path)
- `asset://localhost/<absolute-path>` — scoped file load outside the bundle (the "open user-picked image" path)
- `file://` — **blocked** via nav delegate (matches Tauri's stance; opaque-origin breakage is a footgun)

Scope this brief: macOS + Windows. Linux deferred until the Linux foundation epic starts.

## Why

`file://` URLs have an **opaque origin** (`null`) per the Fetch/HTML spec. This breaks every modern web platform feature that needs a stable origin:

| Feature | `file://` (opaque origin) | `ion://localhost/` (proper origin) |
|---|---|---|
| `history.pushState("/c/cube-42")` | **SecurityError** on WebKit (Mac/Linux) | works |
| `localStorage` scoping | shared/wiped randomly across all `file://` URLs | scoped per origin |
| `fetch("/api")` CORS | reject (`null` matches nothing, not even itself) | same-origin |
| Service Worker registration | spec-blocked on opaque origin | allowed |
| COOP / COEP / `SharedArrayBuffer` | disabled | available |
| Cookies | broken | work |

ion is a **runtime** — it can't assume consumers will hash-route around this (the MyApp-Expo escape hatch). Shipping the proper primitive is the runtime's job.

Reference: Tauri solved this 3 years ago with `tauri://localhost`. We follow that pattern (verified at `~/metascript/refs/tauri/crates/tauri/src/manager/mod.rs:339-346` and `crates/tauri/src/app.rs:2059-2099`).

## Architectural decisions (locked)

| # | Decision | Rationale |
|---|---|---|
| **D1** | Two schemes: `ion://` (bundle SPA) + `asset://` (scoped disk file) | Mirrors Tauri's `tauri://` + `asset://` split. Different access patterns, different scopes. |
| **D2** | Block `file://` in nav delegate (Mac + Win) | Tauri-style strict-by-default. Prevents footgun where consumer loads `<img src="file://...">` from `ion://` page and hits cross-origin rejection. |
| **D3** | Static file mapping only (v0). No dynamic MS handler. | Bridge stays string-only → no MS↔C function pointer FFI → no MS Bug 5 risk → no thread-marshalling. Covers 95% of consumers. Dynamic v1 adds same registry. |
| **D4** | `registerStaticProtocol()` MUST be called BEFORE `open()` | Unified rule across 3 platforms: Mac needs config-time setup, Win needs env-options-before-factory, Linux (future) needs web-context-init. After `open()`, returns `false` + warn. |
| **D5** | Scheme normalized to `<scheme>://localhost/<path>` on all platforms | WebView2 1.0.992+ supports custom schemes natively. ion does NOT need wry's `http://<scheme>.localhost` workaround. If WebView2 hits a snag in implementation, document as risk and fall back. |
| **D6** | Sync handler in v0 (full read into memory) | MyApp bundle ~few MB, sync disk read fast enough. Async/streaming defers to v1 when concrete need arises. |
| **D7** | MIME autodetect from extension, lookup table in `common/mime.c` | Plain table, no library. List below. |
| **D8** | Path traversal blocked: requests with `..` segments rejected with 403 | Defense-in-depth even though baseDir is consumer-controlled. |
| **D9** | `asset://` requires explicit scope allowlist | Consumer calls `registerAssetScope([root1, root2, ...])` once. Requests outside allowed roots return 403. |
| **D10** | `examples/helloWebview.ms` migrates to `ion://localhost/hello.html` | Canonical example shows the correct pattern. `hello.html` already ships via `--asset=` bundling. |

## API surface (MS-side)

### `src/protocol.ms` (new, ~50 LOC)

```ms
import {
    ionRegisterStaticProtocol,
    ionRegisterAssetScope,
} from "./platform/bridge.h";
import { jsEscape } from "./internal/jsEscape";

// Register `<scheme>://localhost/<path>` → `<baseDir>/<path>` static mapping.
// MUST be called BEFORE open(). After open() returns false + logs warning.
//
// Path semantics:
//   - Query string + fragment stripped before lookup
//   - URL-percent-decoded
//   - `..` segments rejected (403)
//   - MIME autodetected from file extension
//   - 404 if file not under baseDir
//
// Origin gotcha:
//   Pages load with origin `<scheme>://localhost`. fetch() to external HTTPS
//   needs CORS allow on this origin. ion IPC (ipc.invoke) is unaffected.
export function registerStaticProtocol(scheme: string, baseDir: string): boolean {
    return ionRegisterStaticProtocol(scheme, baseDir) === 1;
}

// Register an allowlist of root paths that `asset://localhost/<abs-path>`
// requests may serve. Requests for paths NOT under any registered root
// return 403. MUST be called BEFORE open().
//
// Use for: file-picker results, user-selected images/videos, any disk read
// that's not part of the bundled SPA.
export function registerAssetScope(allowedRoots: string[]): boolean {
    // Pass roots as newline-joined string to keep bridge simple; C side splits.
    const joined = allowedRoots.join("\n");
    return ionRegisterAssetScope(joined) === 1;
}
```

### `src/window.ms` (modify)

When `open(...)` is called with an `ion://` URL and no `ion` scheme registered yet, **auto-register** `ion` → `ionResourcePath()`. Zero-config path for the common case.

```ms
// After ionInit(), before ionOpen():
if (url.startsWith("ion://") && !_ionSchemeRegistered) {
    const res = resourcePath();
    if (res !== "") {
        registerStaticProtocol("ion", res);
        _ionSchemeRegistered = true;
    }
}
```

### Bridge (`src/platform/bridge.h`) — additions

```c
// Register a static file-mapping URI scheme. baseDir resolved at registration
// time, then immutable. Path traversal blocked. Returns:
//   1 — registered
//   0 — called after ionOpen() / scheme conflict / baseDir not readable
int ionRegisterStaticProtocol(const char *scheme, const char *baseDir);

// Register asset:// scope. allowedRoots is newline-separated absolute paths.
// Returns:
//   1 — registered
//   0 — called after ionOpen()
int ionRegisterAssetScope(const char *allowedRoots);
```

## File map

### Already done (macOS shipped 2026-05-18)

| File | Status |
|---|---|
| `src/protocol.ms` | ✅ NEW — `registerStaticProtocol`, `registerAssetScope` MS wrapper |
| `src/platform/common/mime.c` + `.h` | ✅ NEW — extension → MIME lookup (17 types) |
| `src/platform/common/protoReg.c` + `.h` | ✅ NEW — cross-platform registry (`ionProtoRegister`, `ionProtoLookup`, freeze) |
| `src/platform/macos/webview/protocol.m` | ✅ NEW — `WKURLSchemeHandler` + `ionInstallSchemeHandlers` |
| `src/platform/macos/webview/bootstrap.m` | ✅ MODIFIED — wires `ionInstallSchemeHandlers(cfg)` before `WKWebView` alloc |
| `src/platform/macos/webview/nav_delegate.m` | ✅ MODIFIED — handles `ION_NAV_BLOCK` for `file://` |
| `src/platform/macos/core/window.m` | ✅ MODIFIED — calls `ionProtoFreeze()` at `ionOpen` |
| `src/platform/common/navpolicy.{c,h}` | ✅ MODIFIED — `file://` rule changed to `ION_NAV_BLOCK` |
| `src/platform/bridge.h` | ✅ MODIFIED — `ionRegisterStaticProtocol` + `ionRegisterAssetScope` decls |
| `src/window.ms` | ✅ MODIFIED — auto-register `ion://` to `resourcePath()` on `open()` |
| `src/index.ms` | ✅ MODIFIED — re-exports |
| `src/ipc.ms` | ✅ MODIFIED — `@compile` lines for new files added |
| `examples/helloWebview.ms` | ✅ MIGRATED — uses `ion://localhost/hello.html`, smoke test passes as `.app` |
| `examples/protocolDemo.ms` | ✅ NEW — verifies pushState + localStorage + proper origin |
| `examples/demoAssets/{index.html,style.css,app.js}` | ✅ NEW — SPA test bundle |
| `README.md` | ✅ MODIFIED — Custom URI Schemes section + origin gotcha note |
| `CHANGELOG.md` | ✅ MODIFIED — Phase 4.5 entry |

### Already done (Windows shipped 2026-05-18 PM)

| File | Status |
|---|---|
| `src/platform/windows/webview/protocol.cpp` | ✅ NEW — `IonEnvOptions` implements **ALL 8 versions** of `ICoreWebView2EnvironmentOptions` (v1-v8 via C++ multi-inheritance, hand-rolled IUnknown). `IonCustomSchemeReg` per-scheme COM bag. `WebResourceRequestedHandler` reads `ionProtoLookup`, builds response via `env->CreateWebResourceResponse` + `SHCreateMemStream` (needs `-lshlwapi`). |
| `src/platform/windows/webview/controller.cpp` | ✅ MODIFIED — `ionBuildEnvOptions()` called before `CreateCoreWebView2EnvironmentWithOptions`; `ionAttachResourceHandler` after webview; env stashed in `WebView2State::env` (needed for `CreateWebResourceResponse`). |
| `src/platform/windows/webview/nav.cpp` | ✅ MODIFIED — handles `ION_NAV_BLOCK` for `file://`. |
| `src/platform/windows/webview/internal.hpp` | ✅ MODIFIED — `WebView2State` gets `env` + `resourceRequestedToken`; declares helpers. |
| `src/platform/windows/core/window.c` | ✅ MODIFIED — calls `ionProtoFreeze()` at `ionOpen`. |
| `src/ipc.ms` | ✅ MODIFIED — `@compile("./platform/windows/webview/protocol.cpp")` + `@passL("-lshlwapi")` added. |
| `std/process/errors.ms` (recompiler-side) | ✅ MODIFIED — `ProcessError` fields renamed `stdout`→`output`, `stderr`→`errorOutput` (lowercase collide with Win `<stdio.h>` macros). |

**Critical landmines discovered during Win port** (documented for future maintainers):

1. **`get_TargetCompatibleBrowserVersion` MUST return a non-empty version string.** Empty `""` triggers `CreateCoreWebView2EnvironmentWithOptions → E_INVALIDARG (0x80070057)`. Current value: `L"130.0.2849.39"` (matches `CORE_WEBVIEW_TARGET_PRODUCT_VERSION` in SDK 1.0.2849.39).

2. **WebView2 QIs for v1–v8** to validate env options. Missing inheritance for ANY version that the runtime knows about → graceful `E_NOINTERFACE` for newer versions (e.g., v9 IID `0ea2394c-…` returned `E_NOINTERFACE` and WebView2 accepted that gracefully), but missing v7's `ChannelSearchKind`/`ReleaseChannels` props will fail validation.

3. **`get_*` string properties MUST return `CoTaskMemAlloc`'d strings, never `nullptr`.** Returning `nullptr` causes E_INVALIDARG. Empty string requires `CoTaskMemAlloc(sizeof(wchar_t))` + `[0]=0`.

4. **WRL `wrl/implements.h` is NOT present in zig's bundled MinGW** (only `wrl/client.h` for `ComPtr`). The SDK's `CoreWebView2EnvironmentOptions` template class requires `Implements<>` — unusable in zig-cross-compile workflow. Hand-roll the 8-interface MI by hand.

## MIME table (lock)

| Extension | MIME |
|---|---|
| `.html`, `.htm` | `text/html; charset=utf-8` |
| `.js`, `.mjs` | `application/javascript; charset=utf-8` |
| `.css` | `text/css; charset=utf-8` |
| `.json` | `application/json; charset=utf-8` |
| `.svg` | `image/svg+xml` |
| `.png` | `image/png` |
| `.jpg`, `.jpeg` | `image/jpeg` |
| `.gif` | `image/gif` |
| `.webp` | `image/webp` |
| `.woff2` | `font/woff2` |
| `.woff` | `font/woff` |
| `.wasm` | `application/wasm` |
| `.map` | `application/json` |
| else | `application/octet-stream` |

## Platform implementation notes

### macOS — `WKURLSchemeHandler`

- Implement Obj-C class `IonProtocolHandler : NSObject <WKURLSchemeHandler>`
- Required methods: `webView:startURLSchemeTask:` (entry) + `webView:stopURLSchemeTask:` (cancel)
- In `startURLSchemeTask:`:
  1. Extract `task.request.URL` → scheme + path
  2. Strip query/fragment, percent-decode path
  3. Call `proto_reg_lookup(scheme, path)` → `(bytes, mime, status)`
  4. Build `NSHTTPURLResponse` with status + Content-Type header
  5. `[task didReceiveResponse:] → [task didReceiveData:] → [task didFinish]`
  6. On error: `[task didFailWithError:]`
- Register via `[config setURLSchemeHandler:handler forURLScheme:@(scheme)]` in `bootstrap.m` BEFORE `WKWebView` instantiation
- **Thread**: callback fires on WebKit main thread. C-side registry is immutable after `open()` → safe by construction.

### Windows — WebView2 `WebResourceRequested`

- Implement IUnknown-style C++ class `WebResourceRequestedHandler` (mirror `AddScriptCompletedCallback` pattern in `controller.cpp`)
- Required IID: `ICoreWebView2WebResourceRequestedEventHandler`
- In `Invoke(sender, args)`:
  1. Get `args->get_Request()` → request URI + method
  2. Parse scheme + path
  3. Call `proto_reg_lookup`
  4. `env->CreateWebResourceResponse(...)` with body stream (`SHCreateMemStream`) + status + Content-Type header
  5. `args->put_Response(response)`
- Register via:
  - `CustomSchemeRegistration` in `CoreWebView2EnvironmentOptions::SetCustomSchemeRegistrations` (BEFORE `CreateCoreWebView2EnvironmentWithOptions`)
  - `webview->AddWebResourceRequestedFilter(L"<scheme>://*", COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL)` (after webview exists)
  - `webview->add_WebResourceRequested(handler, &token)` (attach handler)
- **Thread**: COM thread. Same immutable-registry safety.

### Linux — DEFERRED

Linux ion port is not started (`vendor/ion/CLAUDE.md`: "Linux port — planned, not started, ~1.5-2x macOS effort"). When that epic begins, plug in:
- `webkit_web_context_register_uri_scheme(ctx, "<scheme>", callback, NULL, NULL)` at WebContext init
- Callback uses `webkit_uri_scheme_request_finish(request, stream, length, mime)` to respond
- **Linux quirk** (verified `tauri-runtime-wry/src/lib.rs:5121-5136`): scheme can only register once per WebContext. Must register all schemes at context init.

This brief does NOT include Linux work; it ships as part of the Linux foundation epic.

## Effort estimate vs actual

| Phase | Estimate | Actual |
|---|---|---|
| macOS (`WKURLSchemeHandler` + `bootstrap.m` wiring + `nav_delegate.m` file block) | 2.5 days | ✅ done |
| `protoReg.c` / `mime.c` cross-platform | 1 day | ✅ done |
| `asset://` scope handling (allowlist check shared logic) | 0.5 days | ✅ done |
| `examples/protocolDemo.ms` + migrate `helloWebview.ms` | 0.5 days | ✅ done |
| Tests + README + CHANGELOG | 0.5 days | ✅ done |
| Windows (WebView2 env options + `WebResourceRequested` COM handler + `nav.cpp` file block + 8-interface MI debugging) | 3 days | ✅ done same day (1 day) |
| **Total** | **~8 days** | **~5.5 days actual** (faster than est. — Win debugging found env options validation gotcha quickly via stderr-wrap diagnostic) |

## Acceptance criteria

| # | Criterion | macOS | Windows |
|---|---|---|---|
| 1 | Build green: no compile / linker errors | ✅ 47 modules linked | ⏳ |
| 2 | `examples/protocolDemo.ms` runs: webview opens `demo://localhost/index.html`, displays content, navigates routes, persists localStorage | ✅ `MS ← demo.ready: demo://localhost` verified (origin proper) | ⏳ |
| 3 | `examples/helloWebview.ms` runs (migrated): `ion://localhost/hello.html` loads, IPC invoke + adversarial probe + hotkey all pass per `CLAUDE.md` smoke test | ✅ all markers logged via `.app` bundle smoke | ⏳ |
| 4 | `file://` blocked: console.warn logged, navigation cancelled | ✅ nav_delegate.m wired | ⏳ nav.cpp pending |
| 5 | Path traversal blocked: `../../etc/passwd` returns 403, never escapes baseDir | ✅ `pathIsSafe` in protoReg.c | shared logic |
| 6 | MIME correct: `.png` → `image/png`, `.js` → `application/javascript`, etc. | ✅ `ionMimeForPath` table | shared logic |
| 7 | `asset://` scope enforced: allowlist roots respected, outside returns 403 | ✅ `pathUnderRoot` check | shared logic |
| 8 | MyApp integration smoke: webview loads bundled Expo SPA via `ion://localhost/dist/index.html`, SPA pushState routes succeed (no SecurityError) | post-merge | post-Windows |

**macOS verification log (2026-05-18 06:32):**
```
[webview log] auto-probe: ipc alive
MS ← ping: autoprobe
MS command addNumbers(100, 23)
[ion] IPC rejected: invalid invoke_key
[webview log] auto-call addNumbers result: 123
MS ← ping: hello@2026-05-17T23:32:03.302Z
MS ← hotkey id=1
```
Plus protocolDemo: `MS ← demo.ready: demo://localhost` (proves proper origin via custom scheme).

**Windows verification log (2026-05-18 09:54, Parallels VM):**
```
[ion-debug] IonEnvOpts::QI: → v4 OK (CustomSchemeRegistrations)
[ion-debug] v4::GetCustomSchemeRegistrations called
[ion-debug] WebResourceRequested fired   ← ion://localhost/hello.html intercepted
[webview log] auto-probe: ipc alive       ← page loaded + bootstrap ran
MS ← ping: autoprobe
MS command addNumbers(100, 23)
```
Window shows ion v0 demo page with localStorage write/restore + external-link routing all functional. Confirms `ion://localhost` proper origin works on Windows.

## Risks / gotchas

| # | Risk | Mitigation |
|---|---|---|
| 1 | Windows: `SetCustomSchemeRegistrations` must run BEFORE env factory. Current `controller.cpp` async chain creates env unconditionally in `ionOpen()`. Reorder needed. | Read `controller.cpp` "Async init chain" comment block first. Add registry-read between `LoadLibraryW` and the factory call. |
| 2 | macOS: `WKURLSchemeHandler` callbacks fire on WebKit main thread. C-side `proto_reg_lookup` reads immutable registry — safe by construction. | Document the immutability contract: registry frozen after `open()`. No mutex. |
| 3 | URLs with query string / fragment (`ion://localhost/index.html?v=1#section`) — must strip before disk lookup. | `proto_reg_lookup` strips `?` and `#` before joining with baseDir. Pattern verified against `protocol/tauri.rs:85-95`. |
| 4 | URL-percent-encoded paths (`ion://localhost/c%20space.html`) — must decode before lookup. | Hand-roll percent-decode in `protoreg.c` (~10 LOC). |
| 5 | Build directives quirk — per `vendor/ion/CLAUDE.md` "Build Directives", new `.m`/`.cpp`/`.c` files MUST be added to `@compile` lists in `src/ipc.ms`, NOT in `protocol.ms`. Symptom of getting wrong: linker undef symbols. | Mirror existing `@compile("./platform/macos/...")` entries at `src/ipc.ms:36-49`. |
| 6 | MS Bug 5 — current v0 stores no function values (string-only API) → safe. If v1 dynamic handler is ever added, MUST use parallel-array workaround (`_schemes: string[]` + `_handlers: Handler[]`) like `command.ms`. | Document in v1-plan comment in `protocol.ms`. |
| 7 | WebView2 custom scheme support requires `1.0.992+`. Currently pinned `1.0.2849.39` (per `CLAUDE.md`) — way newer, safe. | No mitigation needed; just verify SDK pin doesn't downgrade. |
| 8 | helloWebview migration: `--asset=examples/hello.html` flag stages `hello.html` at bundle root, but `ionResourcePath()` returns `Contents/Resources/`. Verify the file ends up at `<res>/hello.html`. | Test: `ls out/MyApp.app/Contents/Resources/hello.html` after bundle. |

## Co-evolution

If MS recompiler / std lib limitations bite during implementation (e.g., binary `Uint8Array` handling, string encoding edge cases at FFI boundary), follow `vendor/ion/CLAUDE.md` Co-Evolution Policy:
1. Stop ion work
2. Reproduce minimally in `/tmp/ms-probe/`
3. File in `the MetaScript compiler bug tracker`
4. Either fix in `~/metascript/recompiler/` (separate brief from Sơn required) OR document workaround at the parked site
5. Never silently degrade code style

## Authorization to proceed

`feedback_compiler-edits-need-explicit-go-ahead` in user memory applies to recompiler edits only. **This brief is the explicit go-ahead for ion-source edits** under `vendor/ion/src/`. If implementation surfaces a recompiler edit need, that's a separate brief from Sơn.

## References

- Tauri source: `~/metascript/refs/tauri/`
  - `crates/tauri/src/manager/mod.rs:339-346` — scheme URL builder
  - `crates/tauri/src/app.rs:2059-2099` — `register_uri_scheme_protocol` docs (3-platform API)
  - `crates/tauri/src/protocol/tauri.rs:85-115` — path strip + percent decode
  - `crates/tauri/src/protocol/asset.rs` — `asset://` scope handling reference
  - `crates/tauri-runtime-wry/src/lib.rs:5118-5148` — Linux quirk + wry call shape
- ion existing patterns to mirror:
  - `src/security.ms` — MS wrapper template (15 LOC)
  - `src/platform/macos/security/content_protect.m` — Obj-C platform impl template
  - `src/platform/windows/webview/controller.cpp` — WebView2 COM IUnknown pattern (mirror for protocol handler)
  - `src/platform/macos/webview/nav_delegate.m` — nav delegate to extend for `file://` block
  - `src/command.ms` — parallel-array workaround for MS Bug 5 (reference if v1 dynamic handler ever lands)
