# Ion Render Surface

Generic native rendering inside an Ion window, composited seamlessly with the webview.

Ion is a webview shell. A **render surface** lets an app host a *native* rendering layer (Metal / GL / a whole game engine view) in the same window, z-ordered against the WKWebView/WebView2. Ion has **no opinion on what draws into it** — a Godot game, a hand-written Metal/wgpu renderer, an SDL_Renderer, a video decoder. Renderer-agnostic by design.

## What it is

- A native layer/view that lives in the window's content view, **below or above** the webview, with native compositing (no copying pixels through JS, no canvas).
- Two ways to populate it: **adopt** an existing native view, or **render into** a layer Ion hands you.
- Transparency, z-order, and frame-sync — handled by Ion, the same way across platforms.

## What it is not

- Not a renderer. Ion never draws game/3D content — it only hosts and composites a surface someone else fills.
- Not engine-specific. The public API never mentions Godot/Unity/etc. Those are *consumers* (see the example at the end).
- Not a multi-window manager. A surface belongs to one window.
- Not a frame clock. Ion does not own a render timer in v0 — the app drives its renderer from the existing MS event loop (see "Driving the renderer").

---

## The model

One window, two composited planes:

```
Ion window (SDL3 NSWindow / Win32 HWND) → contentView / DirectComposition tree
  ├─ render surface   (native: adopted NSView / Ion-owned CAMetalLayer / composition swapchain visual)
  └─ webview          (WKWebView / WebView2 CompositionController visual)
```

z-order is explicit per surface: `Below` the webview (the surface is a backdrop the web UI overlays — HUD/launcher chrome on top of a game) or `Above` (the surface is an overlay over web content). Multiple surfaces may coexist with a defined stack order.

When a `Below` surface is present, Ion makes the webview **transparent** (`drawsBackground = NO` on macOS, transparent background on WebView2) so the surface shows through wherever the web page is transparent.

A surface is bound to a window by its `IonWindowId` and identified by an opaque `IonRenderSurfaceId` — the same free-function + id shape as the existing window API (`ionCreateWindow` → `IonWindowId`), not an object/method API.

---

## Bridge contract (`platform/bridge.h`)

Pure C, no Cocoa/Win32 types in signatures — same rule as the rest of the bridge, so the MS-side import stays portable. The native view a consumer adopts crosses the boundary as an opaque `void *` (`Ptr<void>` on the MS side).

```c
typedef int IonRenderSurfaceId;
#define ION_RENDER_SURFACE_INVALID (-1)

// z-order relative to the window's webview
#define ION_SURFACE_BELOW 0
#define ION_SURFACE_ABOVE 1

// input-region modes (see "Compositing & input")
#define ION_INPUT_NONE 0   // all pointer/keyboard input → webview
#define ION_INPUT_FULL 1   // all input → surface
#define ION_INPUT_RECT 2   // input inside (x,y,w,h) → surface, else webview

// Create a surface in `win`, positioned below/above its webview.
// Returns ION_RENDER_SURFACE_INVALID if the window id is unknown.
IonRenderSurfaceId ionRenderSurfaceCreate(IonWindowId win, int z);

// Mode A — adopt a native view the renderer already owns (NSView* / HWND).
// Ion reparents it into the window at the surface's z-slot. No-op if surf invalid.
void  ionRenderSurfaceAdopt(IonRenderSurfaceId surf, void *nativeView);

// Mode B — Ion owns the surface; returns a layer the renderer draws into
// (CAMetalLayer* on macOS / swapchain composition target on Windows).
// Returns NULL if surf invalid or already in adopt mode.
void *ionRenderSurfaceLayer(IonRenderSurfaceId surf);

// Composite + lifecycle. All silently no-op when surf is invalid.
void  ionRenderSurfaceSetVisible(IonRenderSurfaceId surf, int visible);
void  ionRenderSurfaceSyncFrame(IonRenderSurfaceId surf);                 // match content-view bounds; auto on resize
void  ionRenderSurfaceSetInputRegion(IonRenderSurfaceId surf,
                                      int mode, int x, int y, int w, int h);
void  ionRenderSurfaceRelease(IonRenderSurfaceId surf);                   // detach + destroy
```

---

## API (MetaScript)

Free functions over the bridge, taking a typed `Window` handle (from `windowManager.createWindow`) and returning an opaque `RenderSurfaceId`. Constants are `int32` consts mirroring `bridge.h`, the same house style as `windowManager.ms`'s window flags (not MS `enum`s).

```ms
// z-order relative to the webview
export const SurfaceBelow: int32 = 0;
export const SurfaceAbove: int32 = 1;

// input-region modes
export const InputNone: int32 = 0;   // input → webview (passive backdrop)
export const InputFull: int32 = 1;   // input → surface (game primary)
export const InputRect: int32 = 2;   // input inside rect → surface, else webview

export type RenderSurfaceId = int32;
export const RenderSurfaceInvalid: RenderSurfaceId = -1;

// Create a surface bound to a window, positioned relative to the webview.
export function renderSurfaceCreate(win: Window, z: int32): RenderSurfaceId;

// --- populate it (pick one mode) ---

// Mode A — adopt: the renderer already owns a native view; Ion reparents it.
export function renderSurfaceAdopt(surf: RenderSurfaceId, nativeView: Ptr<void>): void;

// Mode B — layer: Ion owns the surface; the renderer draws into it.
export function renderSurfaceLayer(surf: RenderSurfaceId): Ptr<void>;

// --- composite + lifecycle ---
export function renderSurfaceSetVisible(surf: RenderSurfaceId, visible: boolean): void;
export function renderSurfaceSyncFrame(surf: RenderSurfaceId): void;          // match the content view; auto on resize
export function renderSurfaceSetInputRegion(surf: RenderSurfaceId, mode: int32): void;
export function renderSurfaceSetInputRect(surf: RenderSurfaceId, x: int32, y: int32, w: int32, h: int32): void;
export function renderSurfaceRelease(surf: RenderSurfaceId): void;
```

### Two modes

| Mode | Use when | Who owns the surface |
|------|----------|----------------------|
| **A. `renderSurfaceAdopt(surf, view)`** | The renderer creates its own native view (most game engines do) | Renderer — Ion reparents it into the window at the surface's z-slot |
| **B. `renderSurfaceLayer(surf)`** | The renderer draws into a host-provided layer (iOS-style; custom Metal/wgpu) | Ion — creates a `CAMetalLayer` (or swapchain panel) and hands it over |

Both are first-class. A consumer picks whichever fits the renderer it wraps.

---

## Driving the renderer

Ion is **not** a frame clock in v0. The render step is driven by MetaScript, off the loop Ion already runs — `runLoop()` polling `ionPollEvent()` once per tick (`src/ipc.ms`). There is no native timer calling back into MS (a per-frame callback would route a function value through native→MS, which trips a known MS codegen limitation, and would split the engine tick off the loop thread).

Two ways the app interleaves its render step:

1. **`onFrame(fn)` hook** — registers a callback `runLoop` invokes once per poll iteration (`runLoop()`'s signature is unchanged — existing no-arg callers keep working). The consumer drives its engine there (`godotIteration()`). Stored in an array and dispatched via `for-of`, the same shape as `listen` handlers — Bug-5-safe.
2. **App-owned loop** — the consumer writes its own loop calling `ionPollEvent` + its render step, instead of `runLoop`. More control, but re-implements IPC/window-event dispatch.

`renderSurfaceSyncFrame` is called on resize (and may be auto-driven by the window-resize event) to keep the surface matched to the content view.

A native `CVDisplayLink` / DXGI-waitable frame clock — vsync-accurate, independent of the MS loop — is a later enhancement (see Phases), only needed if MS-loop pacing proves insufficient.

---

## Compositing & input

**Compositing** is native — the surface and the webview are sibling views/layers composited by the OS window server. No per-frame pixel copy. The webview is transparent over a `Below` surface.

**Input routing** is the real design concern (a webview hit-tests its whole rect by default). Ion resolves it with the input-region setting + a window-level event tap:

- `InputRegion.Full` — the surface captures all pointer/keyboard input (use in-match: game is primary, web is hidden or a passive HUD).
- `InputRegion.None` — the webview gets everything (use in-launcher: web UI is primary, the surface is a passive backdrop).
- `renderSurfaceSetInputRect(...)` — split: input inside the rect → surface, outside → webview (use for a game viewport framed by web chrome).

Pragmatic default: drive z-order + input region from app **state** (launcher vs in-match) rather than trying to make events fall through a live webview region — that avoids the hard "passthrough a single WKWebView" case. Region-passthrough (web declares transparent input holes via CSS `pointer-events`, Ion forwards) is a later enhancement.

---

## Platform implementation

| | macOS | Windows |
|---|---|---|
| Window | SDL3 → `NSWindow` (`window.m` extracts `contentView`) | plain Win32 `HWND` with a topmost `IDCompositionTarget` |
| Webview | `WKWebView` (subview of contentView — `webview/bootstrap.m`) | WebView2 `CompositionController` hung on a DirectComposition visual; the host forwards mouse input |
| Surface (adopt) | `[contentView addSubview:view positioned:NSWindowBelow/Above relativeTo:webview]` | `SetParent(childHwnd, hostHwnd)`; a child window sits under the whole composition tree, so only `Below` |
| Surface (layer) | `CAMetalLayer` in an `NSView` Ion creates | a DirectComposition visual; the renderer attaches its own `CreateSwapChainForComposition` swapchain (`renderSurfaceAttachSwapChain`) |
| Transparency | `webview.drawsBackground = NO`, window `ION_WIN_TRANSPARENT` | WebView2 `DefaultBackgroundColor` transparent while a `Below` surface exists |
| State storage | new fields on `IonMacWindowState` (`state.h`) | `windows/core/composition.cpp` (single window) |
| Frame clock | MS loop (`runLoop`); `CVDisplayLink` later | MS loop; `DXGI`/`DwmFlush` later |

macOS is the lead target (matches Ion v0). The adopt path slots into `window.m` right where `ionSetupWebview` adds the webview — same `contentView`, just `positioned:NSWindowBelow relativeTo:webview` and `drawsBackground = NO` on the webview. Windows mirrors via the same MS API; `SetParent` cross-process is allowed on Win32, in-process is trivial.

A new `src/platform/macos/core/renderSurface.m` holds the impl; its `@compile("./platform/macos/core/renderSurface.m", "-fobjc-arc")` line goes in the `@platform("macos")` block of `src/ipc.ms` (the canonical bridge-directive home — directives in re-export-only files get dropped).

---

## Consumer example — embedding a Godot game (informative)

This is **not** part of Ion. It shows how a consumer (e.g. a TCG launcher) uses the generic surface to embed a native Godot game built as a library (libgodot), keeping its React launcher in the webview.

```ms
// In the app, not in Ion:
// 1. boot Godot in-process (libgodot_create_godot_instance) — it creates its own NSView
// 2. hand that view to Ion's surface, below the (transparent) launcher webview
// 3. drive the engine from the MS loop's frame hook
const surf = renderSurfaceCreate(win, SurfaceBelow);
renderSurfaceAdopt(surf, godotWindowView());     // godot: window_get_native_handle(WINDOW_VIEW)

onFrame(() => godotIteration());                 // drive the engine on Ion's loop
runLoop();

// in-match:    renderSurfaceSetInputRegion(surf, InputFull);
// in-launcher: renderSurfaceSetInputRegion(surf, InputNone);
```

Everything Godot-specific (booting libgodot, getting `WINDOW_VIEW`, calling `iteration()`) lives in the consumer. Ion only sees a native view + a per-frame call into the consumer's code. Swap Godot for any other native renderer and Ion is unchanged.

---

## Phases

1. **macOS adopt + below** — reparent an external `NSView` under a transparent webview; `runLoop` frame hook; state-driven input region. (Unblocks the Godot/TCG case.)
2. **macOS layer mode** — Ion-owned `CAMetalLayer` for render-into consumers.
3. **Windows parity** — WebView2 + child HWND / swapchain panel.
4. **Native frame clock** — `CVDisplayLink` / DXGI-waitable for vsync-accurate ticking independent of the MS loop.
5. **Region passthrough** — CSS `pointer-events` holes → forwarded input (seamless web-over-native).
