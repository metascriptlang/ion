# Multi-Window Design

Tauri-style generic multi-window support for ion. Every window is a peer —
each has a unique label, its own webview, its own IPC channel. No
"main vs secondary" distinction at the framework level.

## API Surface

### MS Side — Window Lifecycle

```ms
import {
    createWindow, closeWindow, getWindow, getAllWindows,
    setTitle, setSize, setPosition,
    show, hide, focus, minimize, maximize,
    setAlwaysOnTop, setDecorations, setContentProtected,
    emitTo, emitAll, onWindowEvent,
    runLoop,
} from "@metascript/ion";

// Create windows — each identified by a unique label.
const main = createWindow("main", {
    title: "MyApp",
    width: 1280 as int32, height: 800 as int32,
    url: "ion://localhost/index.html",
});

const panel = createWindow("quick-panel", {
    title: "",
    width: 680 as int32, height: 420 as int32,
    url: "ion://localhost/panel.html",
    decorations: false,
    alwaysOnTop: true,
    center: true,
    visible: false,   // hidden until hotkey toggles it
});

// Manage
setTitle(main, "MyApp — v2");
show(panel);
focus(panel);

// Per-window IPC: MS → JS
emitTo("quick-panel", "search-results", payload);
emitAll("theme-changed", newTheme);

// Window events
onWindowEvent((label, event) => {
    if (label === "quick-panel" && event === "blur") hide(panel);
});

// Unified event loop — pumps ALL windows, routes IPC by label
runLoop();
```

### MS Types

```ms
interface WindowOptions {
    title: string;
    width: int32;
    height: int32;
    url: string;
    resizable: boolean;     // default true
    decorations: boolean;   // default true
    alwaysOnTop: boolean;   // default false
    transparent: boolean;   // default false
    visible: boolean;       // default true
    center: boolean;        // default false
    x: int32;               // default -1 (OS decides)
    y: int32;               // default -1 (OS decides)
}

interface Window {
    id: int32;              // internal slot index
    label: string;          // unique identifier
}

// NULL sentinel: createWindow returns null on failure
type MaybeWindow = Window | null;
```

### JS Side — Transport (bootstrap-injected)

The native bootstrap injects the per-window label into the frozen `window.__ion__`
transport object (alongside the existing `post` / `setReceiver`):

```js
window.__ion__.label              // "quick-panel" — NEW
window.__ion__.post(name, payload) // JS → MS, now tags envelope with __label
window.__ion__.setReceiver(fn)     // MS → JS (unchanged)
```

### JS Side — npm package (`@metascriptlang/ion`, web/src/)

This is the half a v0 read misses: the public JS API lives in the npm package
(`web/src/index.ts`), NOT in the bootstrap. v0 it exposes `invoke` / `on` /
`off` / `call`. Multi-window adds three exports — and these are real code
changes to `web/src/index.ts`, not just C:

```ts
import { getCurrentLabel, emitTo, emit } from "@metascriptlang/ion";

// Which window am I? Reads window.__ion__.label
const me = getCurrentLabel();        // "quick-panel"

// Window → window (routes JS → MS → target JS). THE Raycast primitive:
// the panel tells the main window what the user picked.
emitTo("main", "item-picked", JSON.stringify({ id: 42 }));

// Broadcast to every window (including self)
emit("theme-changed", "dark");

// Receive — existing on()/off() unchanged, now also fires for emitTo/emit
on("item-picked", (payload) => { ... });
```

**Why `emitTo` from JS routes through MS**: a webview cannot reach another
webview directly — they're isolated WKWebView/WebView2 instances. JS calls
`__ion__.post("__emit", {target, event, payload})`; MS-side `runLoop`
recognizes the reserved `__emit` channel and forwards via `ionEvalJSWindow`
to the target window's `_dispatch`. Same pattern as the existing `__call`
command channel — one more reserved channel, no new transport.

```
  panel.html                 ion (MS runLoop)              main.html
  ──────────                 ────────────────              ─────────
  emitTo("main",────post────► __emit channel
    "picked", x)              resolve "main" → winId 0
                              ionEvalJSWindow(0, ...)──────► _dispatch
                                                            on("picked") fires
```

### Reserved channel additions

Mirrors the existing `__call` / `__response` pair (protocol.ts ↔ protocol.h):

| Channel | Direction | Envelope | Purpose |
|---------|-----------|----------|---------|
| `__emit` | JS → MS | `{target, event, payload}` | window→window / broadcast routing |
| (existing `__call`/`__response`) | both | `{id, name, args}` / `{id, value}` | command RPC, unchanged |

`target: ""` (empty) means broadcast (`emit`); a label means targeted (`emitTo`).

### Backward Compatibility

v0 `open()` / `close()` / `runLoop()` keep working — they map to:

```ms
// open("Title", 1280, 800, url) → createWindow("main", { ... })
// close() → closeWindow(getWindow("main"))
// runLoop() → unchanged (already pumps events)
```

## C Bridge

### New Functions

```c
typedef int32_t IonWindowId;
#define ION_WINDOW_INVALID (-1)

// Lifecycle
IonWindowId ionCreateWindow(const char *label, const char *title,
                            int width, int height, const char *url,
                            int flags);
void        ionCloseWindow(IonWindowId id);
int         ionWindowCount(void);   // number of live windows

// Properties
void ionSetWindowTitle(IonWindowId id, const char *title);
void ionSetWindowSize(IonWindowId id, int width, int height);
void ionSetWindowPosition(IonWindowId id, int x, int y);
void ionShowWindow(IonWindowId id);
void ionHideWindow(IonWindowId id);
void ionFocusWindow(IonWindowId id);
void ionMinimizeWindow(IonWindowId id);
void ionMaximizeWindow(IonWindowId id);
void ionSetWindowAlwaysOnTop(IonWindowId id, int on);
void ionSetWindowDecorations(IonWindowId id, int on);
void ionSetWindowContentProtected(IonWindowId id, int on);

// Per-window JS eval (replaces global ionEvalJS)
void ionEvalJSWindow(IonWindowId id, const char *js);

// Per-window file dialog (modal to window)
msString ionFileOpenWindow(IonWindowId id);
```

### Modified Functions

```c
// Event pump — unchanged signature, but events now carry window context.
// Return codes:
//   0  idle
//   1  app quit (all windows closed or Cmd+Q)
//   2  IPC message — read windowId/name/payload
//   3  window event — read windowId/eventType
int ionPollEvent(void);

// After ionPollEvent returns 2:
IonWindowId ionMessageWindowId(void);   // NEW — which window
msString    ionMessageName(void);       // existing
msString    ionMessagePayload(void);    // existing

// After ionPollEvent returns 3:
IonWindowId ionWindowEventId(void);     // which window
int         ionWindowEventType(void);   // enum below
```

### Window Flags

```c
#define ION_WIN_RESIZABLE      (1 << 0)   // SDL_WINDOW_RESIZABLE
#define ION_WIN_DECORATIONS    (1 << 1)   // title bar + OS chrome
#define ION_WIN_ALWAYS_ON_TOP  (1 << 2)   // SDL_WINDOW_ALWAYS_ON_TOP
#define ION_WIN_TRANSPARENT    (1 << 3)   // SDL_WINDOW_TRANSPARENT
#define ION_WIN_VISIBLE        (1 << 4)   // show immediately
#define ION_WIN_CENTERED       (1 << 5)   // center on screen

// Default: RESIZABLE | DECORATIONS | VISIBLE
#define ION_WIN_DEFAULT  (ION_WIN_RESIZABLE | ION_WIN_DECORATIONS | ION_WIN_VISIBLE)
```

### Window Event Types

```c
enum {
    ION_EVT_CLOSE_REQUESTED = 1,   // user clicked close button
    ION_EVT_DESTROYED       = 2,   // window actually destroyed
    ION_EVT_FOCUSED         = 3,
    ION_EVT_BLURRED         = 4,
    ION_EVT_RESIZED         = 5,
    ION_EVT_MOVED           = 6,
};
```

### Unchanged (App-Level, Not Per-Window)

These stay as-is — they're process-global, not window-scoped:

- `ionInit()` / `ionQuit()`
- `ionInstallTray()` / `ionInstallTrayImage()` / `ionUninstallTray()`
- `ionNotify()`
- `ionRegisterHotkey()` / `ionUnregisterHotkey()`
- `ionKeychainSet()` / `ionKeychainGet()` / `ionKeychainDelete()`
- `ionRegisterStaticProtocol()` / `ionRegisterAssetScope()`
- `ionUpdate*()` family

## Internal Architecture

### Window Registry (common/)

Replace per-platform globals with a shared slot array:

```c
// common/window_registry.h
#define ION_MAX_WINDOWS 16

typedef struct {
    int    active;           // 0 = free slot, 1 = in use
    char   label[64];        // unique label, NUL-terminated
    void  *platformState;    // opaque → platform-specific struct
} IonWindowSlot;

IonWindowId  ion_registry_alloc(const char *label);
void         ion_registry_free(IonWindowId id);
IonWindowSlot *ion_registry_get(IonWindowId id);
IonWindowId  ion_registry_find(const char *label);
int          ion_registry_count(void);
```

### Per-Platform State

Each platform defines its own struct, stored as `platformState`:

```c
// macOS
typedef struct {
    SDL_Window  *sdlWindow;
    NSWindow    *nsWindow;
    WKWebView   *webview;
    id           navDelegate;
} IonMacWindowState;

// Windows
typedef struct {
    HWND   hwnd;
    void  *webview2State;   // WebView2State* (C++ opaque)
} IonWinWindowState;

// Linux
typedef struct {
    GtkWidget      *window;
    WebKitWebView  *webView;
} IonLinuxWindowState;
```

### IPC Queue

The existing queue gains a window ID field:

```c
typedef struct ion_msg_node {
    IonWindowId          windowId;   // NEW
    char                *name;
    char                *payload;
    struct ion_msg_node *next;
} ion_msg_node_t;

// New push that tags with window ID
int ion_queue_push_w(IonWindowId id, const char *name, const char *payload);

// Last-popped window ID
IonWindowId ion_queue_last_window_id(void);
```

### Window Event Queue

Separate lightweight queue for lifecycle events (avoids mixing with IPC):

```c
// common/window_events.h
typedef struct {
    IonWindowId windowId;
    int         eventType;    // ION_EVT_*
} IonWindowEvent;

int  ion_wevt_push(IonWindowId id, int eventType);
int  ion_wevt_pop(IonWindowEvent *out);  // returns 1 if popped, 0 if empty
```

### Bootstrap Template

Add `%s` slot for window label:

```c
static const char kJsTemplate[] =
    "(function(){"
    "  if (window.self !== window.top) return;"
    "  var __ionKey = '%s';"
    "  var __ionLabel = '%s';"          // NEW
    "  var __recv = null;"
    "  var nativePost = function(envelope) { %s };"
    "  Object.defineProperty(window, '__ion__', {"
    "    value: Object.freeze({"
    "      label: __ionLabel,"          // NEW — expose to JS
    "      post: function(name, payload) {"
    "        nativePost({"
    "          __key: __ionKey,"
    "          __label: __ionLabel,"    // NEW — tag messages
    "          name: String(name),"
    "          payload: payload === undefined || payload === null"
    "            ? '' : String(payload)"
    "        });"
    "      },"
    "      setReceiver: function(fn) { __recv = fn; },"
    "      _dispatch: function(name, payload) {"
    "        if (__recv) __recv(name, payload);"
    "      }"
    "    }),"
    "    writable: false, configurable: false"
    "  });"
    "  // ... console relay, error handlers unchanged"
    "})();";

char *ion_build_bootstrap_js(const char *invokeKey,
                             const char *windowLabel,    // NEW
                             const char *nativePostBody);
```

### Event Pump Changes

```
ionPollEvent()
├── check window event queue → return 3
├── check IPC message queue → return 2
├── SDL_WaitEventTimeout(16ms)
│   ├── SDL_EVENT_QUIT → return 1
│   ├── SDL_EVENT_WINDOW_CLOSE_REQUESTED → push ION_EVT_CLOSE_REQUESTED, return 3
│   ├── SDL_EVENT_WINDOW_FOCUS_GAINED → push ION_EVT_FOCUSED, return 3
│   ├── SDL_EVENT_WINDOW_FOCUS_LOST → push ION_EVT_BLURRED, return 3
│   ├── SDL_EVENT_WINDOW_RESIZED → push ION_EVT_RESIZED, return 3
│   ├── SDL_EVENT_WINDOW_MOVED → push ION_EVT_MOVED, return 3
│   └── other → continue
├── check IPC message queue again → return 2
└── return 0 (idle)
```

SDL3 events carry `windowID` — use `SDL_GetWindowFromID(event.window.windowID)`
to look up which slot it belongs to. This is the key reason SDL3 naturally
supports multi-window with minimal changes.

### MS-Side Dispatch

```ms
export function runLoop(): void {
    let running = true;
    while (running) {
        const evt = ionPollEvent();
        if (evt === 1) {
            running = false;
        } else if (evt === 2) {
            const windowId = ionMessageWindowId();
            const name = ionMessageName();
            const payload = ionMessagePayload();
            const label = labelFromId(windowId);
            // Route to per-window handlers, then global handlers
            dispatchIPC(label, name, payload);
        } else if (evt === 3) {
            const windowId = ionWindowEventId();
            const eventType = ionWindowEventType();
            const label = labelFromId(windowId);
            dispatchWindowEvent(label, eventType);
        }
    }
    // Close all windows
    closeAll();
    ionQuit();
}
```

## Implementation Phases

### Phase 1: Window Registry + C Bridge (macOS first)

Files created:
- `src/platform/common/window_registry.{h,c}`
- `src/platform/common/window_events.{h,c}`

Files modified:
- `src/platform/bridge.h` — add new function declarations
- `src/platform/common/queue.{h,c}` — add `windowId` field
- `src/platform/common/bootstrap.{h,c}` — add `windowLabel` param
- `src/platform/macos/state.{h,m}` — replace globals with `IonMacWindowState`
- `src/platform/macos/core/window.m` — `ionCreateWindow` + `ionCloseWindow`
- `src/platform/macos/webview/bootstrap.m` — pass label to bootstrap
- `src/platform/macos/webview/eval.m` — `ionEvalJSWindow(id, js)`
- `src/platform/macos/webview/poll.m` — multi-window event dispatch

Old functions (`ionOpen`, `ionClose`, `ionEvalJS`) become thin wrappers
that operate on slot 0 ("main" window).

### Phase 2: MS API Layer

Files created:
- `src/windowManager.ms` — registry + `createWindow` / `closeWindow` / properties

Files modified:
- `src/window.ms` — backward-compat `open()` / `close()` via `createWindow`
- `src/ipc.ms` — per-label routing + `emitTo` / `emitAll` + window events + `__emit` channel
- `src/command.ms` — commands tagged with source window label
- `src/security.ms` — `setContentProtected` takes `Window`
- `src/dialog.ms` — `openFile` takes `Window` (modal)
- `src/index.ms` — re-export new API

**JS npm package** (`web/src/`) — the JS half, must ship in lockstep:
- `web/src/index.ts` — add `getCurrentLabel()`, `emit()`, `emitTo()`; make
  `on()` also fire for emit/emitTo-delivered events
- `web/src/protocol.ts` — add `CHANNEL_EMIT = "__emit"` + field constants;
  mirror in `src/platform/common/protocol.h`
- Bump `__ion__` typing in the `declare global` block to include `label`

> Bug 5 reminder (CLAUDE.md): the window registry and per-label handler
> tables must use parallel arrays or `Window[]` structs, NOT
> `Map<string, Handler>` — function-in-container codegen is broken. Same
> workaround `command.ms` already uses (`_cmdNames` + `_cmdFns`).

### Phase 3: Windows + Linux Port

Same registry pattern, platform-specific state struct:
- `src/platform/windows/state.{h,c}` → `IonWinWindowState`
- `src/platform/windows/core/window.c` → multi-window Win32 host
- `src/platform/windows/webview/controller.cpp` → per-window WebView2
- `src/platform/linux/state.{h,c}` → `IonLinuxWindowState`
- `src/platform/linux/core/window.c` → multi-window GTK
- `src/platform/linux/webview/setup.c` → per-window WebKitWebView

### Phase 4: Window Events + Polish

- SDL3 window events → `ION_EVT_*` dispatch
- `onWindowEvent` MS handler
- Close-requested interception (prevent default)
- Focus/blur, resize/move events
- Quit logic: last window closed = app quit (configurable)

## Design Decisions

### Stay thin — what we deliberately do NOT port from Tauri

CLAUDE.md working agreement: "Don't add Tauri-style features MyApp doesn't
need." Multi-window is the sanctioned "add later if needed" feature (README
"What it is not"), but we take only the window primitives, not the framework:

- **No 6-kind `EventTarget` enum** (`Any`/`AnyLabel`/`App`/`Window`/`Webview`/
  `WebviewWindow`). ion targets by label string or broadcast — two cases.
- **No separate Window vs Webview** — 1 window = 1 webview (see below).
- **No event-plugin / `UnlistenFn` / multi-listener-per-event with IDs.** ion
  keeps its v0 model: one handler per name (`on`/`off`), now scoped per window.
  If a real need for multiple listeners appears, add then — don't pre-build.
- **No capability ACL, isolation iframe, FS scope, plugin system** — already
  out of scope in v0, stays out.

### Why label (string) not just int ID?

Tauri pattern. Labels are self-documenting (`"settings"` vs window 3),
stable across restarts, and allow inter-window communication without
passing handles around. The int `IonWindowId` is internal — MS API
exposes `Window.label` as the primary identity.

### Why static array, not dynamic?

16 slots is generous for desktop apps. Static array means:
- No malloc in the registry hot path
- O(1) lookup by ID (array index)
- O(N) lookup by label (N ≤ 16, linear scan is fine)
- No OOM failure mode for window tracking itself

### Why separate window event queue?

IPC messages (JS → MS) and window lifecycle events (OS → MS) have
different shapes. Mixing them in one queue forces type-punning or
envelope overhead. Two queues, same poll loop.

### Why not separate Window/Webview like Tauri?

Tauri v2 separates `Window` (native container) from `Webview` (content)
to allow multiple webviews per window. ion is simpler: 1 window = 1
webview, always. If ion ever needs split panes, the Webview abstraction
can be added later without breaking the Window API.

### SDL3 + multi-window

SDL3 natively supports multiple windows. `SDL_CreateWindow` returns
independent handles. `SDL_WaitEventTimeout` returns events from all
windows, with `event.window.windowID` identifying the source. Our
existing SDL dependency already handles the hard platform abstraction.

macOS: Each `SDL_Window` wraps an `NSWindow`. We extract the Cocoa
handle and attach a `WKWebView` — same as v0, just multiple times.

Windows: SDL is not used (Win32 host window + WebView2). Multi-window
means calling `CreateWindowEx` multiple times — straightforward.

Linux: SDL is not used (GTK3). `gtk_window_new()` for each window,
`webkit_web_view_new()` for each webview.
