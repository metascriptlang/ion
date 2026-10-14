# Window content

How an Ion window holds content, and why it has this shape. The contract itself is
`src/platform/bridge.h`, sections "Windows and their content" and "Webviews"; the MetaScript
surface is `src/windowManager.ms`, `src/webview.ms` and `src/input.ms`.

## The split

Ion is the platform; the app framework (Neon) executes. Decided by the person on 2026-10-14/15
("Ion chỉ là platform/nền tảng, cung cấp runtime/môi trường"; "WebView chỉ là một native
component thôi - không phải root của Ion"; every app goes Ion → Neon → Void, so Ion is no longer a
Tauri alternative).

| concern | Ion | the app (Neon) |
|---|---|---|
| window | OS window, compositor root, D2D-backed device (Windows) | — |
| content | composites what the app attaches | its view tree, Void areas, where each webview sits |
| input | raw window records in device pixels | hit-testing, focus, dispatch, pointer forwarding into webviews |
| loop | OS message pump, vsync clock | what each frame does (`requestFrame`, policies) |
| webview | engine, IPC routed by webview label | placement, bounds, when it gets input and focus |

A window is an empty native root. One mechanism places content: a webview, a Void area and the
app's native views are all nodes the app parents in the window's tree; a full-window `<Void>`
(Terminator, a game) is a node whose frame is the window's bounds, not a separate mode.

## Why the app hit-tests

React Native for Windows does it this way: Fabric hit-tests its own component tree and routes
into foreign content as a leaf (`~/projects/react-native-windows` at `1f59db1`,
`vnext/Microsoft.ReactNative/Fabric/Composition/ContentIslandComponentView.cpp:194-212`,
`CompositionEventHandler.cpp:425-460`), while `ReactNativeWin32App` owns the message loop. Neon has
to hit-test its views anyway, so an element tree in Ion would be a second tree kept in sync with
the first.

Rejected:

- **An element tree with z-order and hit-testing in Ion.** Two trees; a native button over a
  webview needs Ion to know Neon's tree.
- **A content-root API beside the old render surface** (the proposal of 2026-10-14). It kept the
  fixed Above / webview / Below order and Ion's routing (`ionCompRoute`, input regions), which
  cannot put a native view over a webview and still give it the click.
- **A per-window flag for the D2D-backed device.** One more mode; the device is chosen when the
  window is created, so a forgotten flag fails at run time.

The webview follows Tauri 2: `Window::add_child(WebviewBuilder, position, size)`
(`~/metascript/refs/tauri` at `107f93a`, `crates/tauri/src/window/mod.rs:1226`), wry's
`with_bounds` / `build_as_child` (`~/metascript/refs/wry` at `6642074`, `src/lib.rs:1477,1571`), and
IPC routed by the webview's label (`crates/tauri/src/ipc/protocol.rs:32-35`). On Windows the
concrete form is Microsoft's visual-hosting sample: the app owns the DirectComposition root, the
webview renders into a child visual, the app positions it and forwards pointer input with
`SendMouseInput` (`~/projects/WebView2Samples` at `bd0048f`,
`SampleApps/WebView2APISample/ViewComponent.cpp:122-146,586-595,737-842,912-919`).

## Where Ion still chooses a webview itself

Two OS queries are synchronous and cannot wait for a round trip through the app, so Ion picks the
webview by its bounds, preferring the one the app last forwarded pointer input to
(`webviewAt` in `src/platform/windows/webview/host.cpp`):

- **OLE drag and drop.** `IDropTarget::DragOver` must answer with an effect during the drag loop.
- **UI Automation.** `ElementProviderFromPoint` and fragment navigation; the root lists every
  webview as a child. The accessibility tree of the app's native views is the app's to provide.

Touch and pen are no longer routed by Ion: `WM_POINTER*` falls through to `DefWindowProc`, Windows
promotes it to mouse messages, and those reach the app as pointer records like any other.

## Frame clock

One clock per window (`src/platform/common/frameClock.c`, rules pinned by
`test/common/frameClock.ms`). The tick reaches MS as input type 9, so the render step stays on the
loop thread.

| window state | `FrameOnDemand` (application UI) | `FrameContinuous` (game) |
|---|---|---|
| active | one frame per `requestFrame` | every vsync |
| inactive, visible | one frame per request | none, unless `setFrameWhenInactive(win, true)` |
| minimized, or cloaked (Windows) | none; the request waits | none |

Windows learns of a cloak from a WinEvent hook on `EVENT_OBJECT_CLOAKED` / `UNCLOAKED`
(`windows/core/window.c`); a cloaked window is still active and not minimized, so without the hook
it kept its 165 Hz. A resize requests a frame. With nothing due, the Windows loop blocks in
`MsgWaitForMultipleObjectsEx` and the vsync thread parks.

**Windows tick source.** A thread waits on `DCompositionWaitForCompositorClock` (Windows 11) only
while a window is due a frame. `DwmFlush` was measured as the alternative and rejected: the same
165 Hz and the same jitter, but 105% of one core (10.5 s CPU in 10 s), because it busy-waits. A
DXGI frame-latency waitable needs the swapchain created with its flag, and the renderer owns the
swapchain. On Windows 10 the entry point is missing: Ion prints `[ion] frame clock:
DCompositionWaitForCompositorClock not found` and sends no frames.

Measured 2026-09-24, when the clock was keyed per render surface (the tick source is unchanged), on
this Windows 11 box (RTX 5090, 164 Hz display), msc v0.2.55 (build `65985605`), 10 s after 3 s of
warm-up, a D3D11 clear plus `Present(1)` per frame:

| | before: 16 ms poll loop | after: frame clock |
|---|---|---|
| idle (nothing requested) | 33 wakeups/s, ~7 M cycles/s | 0 frames, loop thread 0.000 M cycles/s |
| continuous | 32.0–33.2 Hz, sd 2.1–3.8 ms, p99 up to 47.6 ms | 165.0 Hz, sd 0.07–0.10 ms, p99 6.25–6.32 ms |
| on demand, a click every 100 ms | — | 93 posted clicks → 93 frames |
| continuous, another window active | — | 0 frames; 1657 at 165 Hz with FrameWhenInactive |
| continuous, minimized | — | 0 frames |
| continuous, cloaked 5 s by `DWMWA_CLOAK` | — | 0 frames (801 with the hook removed) |

## Traps measured on Windows

- **`IDCompositionVisual::AddVisual(child, insertAbove, NULL)` inverts `insertAbove`.** With a NULL
  reference, `FALSE` puts the child in front of every sibling and `TRUE` behind them. Measured
  2026-10-15: a badge added last with `TRUE` drew under the webview; with `FALSE` it drew over it.
  The old `ION_SURFACE_ABOVE` path used `TRUE, NULL`, so an "above" surface sat below.
- **A second DComp device's visual parents into Ion's tree** (measured 2026-10-14: `AddVisual`
  and both `Commit`s returned S_OK and its D2D content rendered), but the two devices commit
  separately, so one change can split across two displayed frames. Ion keeps one device.
- **The device on a D2D device hosts WebView2 unchanged** (measured 2026-10-14 and again by the
  examples below).

## Measured

2026-10-15, Windows 11, msc v0.3.3 (`9a4775dc`), WebView2 Runtime installed:

- `examples/nativeContent.ms`: an empty window, a D2D panel with DirectWrite text, a webview child
  at (480,24) 560×520 and a native badge over its corner. Clicks posted to the window's own HWND
  logged `host click: panel at 200,120`, `host click: badge at 980,44` (the badge over the webview
  got the click), and `webview.click: 220,236` from the page for a click at (700,260), so the
  forwarded point is webview-local. A key posted after focus returned to the content logged
  `host key: KeyA`. A `PrintWindow(PW_RENDERFULLCONTENT)` capture showed the panel, the webview and
  the badge drawn over it.
- `examples/helloWebview.ms` through `examples/content/page.ms` (one webview filling the window):
  `auto-probe: ipc alive`, `MS command addNumbers(100, 23)` and the page's `received pong` reply,
  which travels back to the sending webview by id.

Not measured: macOS and Linux (written to this contract on a Windows host, never compiled), a
real foreground session with physical input (the harness cannot take the foreground), IME
composition into the content, more than one window on Windows (one window today).
