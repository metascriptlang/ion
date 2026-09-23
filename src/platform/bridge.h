// Ion native bridge — public C contract between MS and the platform layer.
//
// Same signatures on every platform; implementations live in
// src/platform/<os>/. Linker picks the matching .o files based on the
// @platform("...") block selected at build time (see src/ipc.ms).
//
// v0 scope: single window, single webview, polling event loop.
// Caller (MS) drives the loop via ionPollEvent. Platform callbacks queue
// IPC messages internally; ionPollEvent surfaces them one at a time.
//
// Pure C — no Cocoa/Win32/WebView types in signatures so MS-side import
// stays portable.

#ifndef ION_BRIDGE_H
#define ION_BRIDGE_H

// Bridge functions returning text use msString (MS native string), not
// const char*. This matches MS std/ convention (os.h, process.h, crypto/)
// and gives clean call sites on the MS side — no fromC wrappers needed.
// See ~/metascript/recompiler/docs/LANG-INTERLOP.md "Current state vs intent".
#include "runtime/core/string.h"
#include "common/windowRegistry.h"   // IonWindowId, ION_WINDOW_INVALID

// Lifecycle.
int  ionInit(void);
void ionQuit(void);

// ---- Single-window (legacy v0 API) ---------------------------------------
//
// These wrappers operate on the window with label "main". They exist for
// backward compatibility with v0 apps. Multi-window apps should use the
// ionCreateWindow / ionEvalJSWindow / ionCloseWindow path below.
//
// ionOpen: creates (or replaces) the "main" window. Returns 1 on success,
// 0 on failure. ionClose closes "main" if present.
int  ionOpen(const char *title, int width, int height, const char *url);
void ionClose(void);

// ---- Multi-window API ----------------------------------------------------
//
// Each window is identified by a unique string `label`. The registry holds
// up to ION_MAX_WINDOWS slots. Operations on a destroyed/unknown id are no-ops.
//
// Window creation flags — bitmask passed to ionCreateWindow.
#define ION_WIN_RESIZABLE      (1 << 0)
#define ION_WIN_DECORATIONS    (1 << 1)
#define ION_WIN_ALWAYS_ON_TOP  (1 << 2)
#define ION_WIN_TRANSPARENT    (1 << 3)
#define ION_WIN_VISIBLE        (1 << 4)
#define ION_WIN_CENTERED       (1 << 5)
#define ION_WIN_FULLSCREEN     (1 << 6)
#define ION_WIN_DEFAULT        (ION_WIN_RESIZABLE | ION_WIN_DECORATIONS | ION_WIN_VISIBLE)

// Create a window. Returns the window id or ION_WINDOW_INVALID if:
//   - label is NULL/empty/duplicate/over ION_LABEL_MAX
//   - all ION_MAX_WINDOWS slots are taken
//   - native creation failed
IonWindowId ionCreateWindow(const char *label, const char *title,
                            int width, int height, const char *url, int flags);

// Close a window by id. Safe to call with ION_WINDOW_INVALID.
void        ionCloseWindow(IonWindowId id);

// Number of live windows.
int         ionWindowCount(void);

// Look up a window by label. Returns ION_WINDOW_INVALID if no live window
// has the label. Pure registry lookup — same impl on every platform.
IonWindowId ionFindWindow(const char *label);

// Get the label of a live window, or "" if the id is invalid.
msString    ionWindowLabel(IonWindowId id);

// Evaluate `js` in the target window's webview. No-op if id is invalid.
// Replaces ionEvalJS for multi-window callers; ionEvalJS targets "main".
void        ionEvalJSWindow(IonWindowId id, const char *js);

// Window properties. All silently no-op when id is invalid.
void        ionShowWindow(IonWindowId id);
void        ionHideWindow(IonWindowId id);
void        ionFocusWindow(IonWindowId id);
void        ionMinimizeWindow(IonWindowId id);
void        ionMaximizeWindow(IonWindowId id);
void        ionSetWindowTitle(IonWindowId id, const char *title);
void        ionSetWindowSize(IonWindowId id, int width, int height);
void        ionSetWindowPosition(IonWindowId id, int x, int y);
void        ionSetWindowAlwaysOnTop(IonWindowId id, int on);
void        ionSetWindowDecorations(IonWindowId id, int on);
void        ionSetWindowContentProtected(IonWindowId id, int on);

// Current drawable size of the window in PIXELS (content area × backing scale).
// A render-surface consumer reads this on a resize event to re-size its native
// renderer (e.g. Godot's embedded display server) to the new window size.
// 0 if the id is invalid.
int         ionWindowPixelWidth(IonWindowId id);
int         ionWindowPixelHeight(IonWindowId id);

// Per-window file picker. The window param is reserved for future window-
// modal sheet behavior; currently it's application-modal, identical to
// ionFileOpen. Empty string on cancel.
msString    ionFileOpenWindow(IonWindowId id);

// ---- Render surface ------------------------------------------------------
//
// A native rendering layer (Metal / GL / a whole engine view) hosted in a
// window, z-ordered against the webview. Ion only hosts + composites — it
// never draws into the surface. The renderer (a game engine, a custom Metal
// pass, a video decoder) owns the pixels. See docs/RENDER-SURFACE.md.
//
// The adopted native view crosses the boundary as an opaque void* (NSView*
// on macOS, HWND on Windows) — same pure-C rule as the rest of the bridge.

typedef int IonRenderSurfaceId;
#define ION_RENDER_SURFACE_INVALID (-1)

// z-order relative to the window's webview.
#define ION_SURFACE_BELOW 0
#define ION_SURFACE_ABOVE 1

// input-region modes — where OS pointer/keyboard input is routed.
#define ION_INPUT_NONE 0   // all input → webview (surface is a passive backdrop)
#define ION_INPUT_FULL 1   // all input → surface (game primary)
#define ION_INPUT_RECT 2   // input inside (x,y,w,h) → surface, else webview

// Create a surface in `win`, positioned below/above its webview. Returns
// ION_RENDER_SURFACE_INVALID if the window id is unknown/closed or no slot
// is free.
IonRenderSurfaceId ionRenderSurfaceCreate(IonWindowId win, int z);

// Mode A — adopt a native view the renderer already owns. Ion reparents it
// into the window at the surface's z-slot. No-op if surf invalid or view NULL.
void  ionRenderSurfaceAdopt(IonRenderSurfaceId surf, void *nativeView);

// Mode A2 (macOS) — adopt a CALayer the renderer draws into (e.g. an embedded
// engine's CAMetalLayer), embedding it directly into the window at the
// surface's z-slot. In-process layer sharing — no NSView, no CAContext.
// caLayer is the CALayer pointer passed as an integer (raw value across the MS
// boundary — a Ptr would be boxed/refcounted).
void  ionRenderSurfaceAdoptLayer(IonRenderSurfaceId surf, long long caLayer);

// Mode B — Ion owns the surface; returns a layer the renderer draws into
// (CAMetalLayer* on macOS). NULL on Windows, where Mode B is
// ionRenderSurfaceAttachSwapChain.
void *ionRenderSurfaceLayer(IonRenderSurfaceId surf);

// Mode B (Windows) — the renderer creates an IDXGISwapChain1 with
// CreateSwapChainForComposition (premultiplied alpha, flip model) on its own
// D3D11 device, sized to the ION_INPUT_RESIZE pixel size; Ion makes it the
// content of the surface's DirectComposition visual. The pointer crosses as
// an integer for the same reason as caLayer above. Returns 1 on success, 0 on
// an invalid surface or swapchain; always 0 on macOS and Linux.
int   ionRenderSurfaceAttachSwapChain(IonRenderSurfaceId surf, long long dxgiSwapChain1);

// Where the IME draws its candidate window: the caret rect in device pixels,
// top-left of the surface. Set it whenever the caret moves.
void  ionRenderSurfaceSetImeRect(IonRenderSurfaceId surf, int x, int y, int w, int h);

// Low-latency input: a sink the surface host view calls DIRECTLY (main thread,
// inside event processing) for each mouse event, bypassing the ionPollEvent
// queue + MS round-trip. The renderer injects straight into its input buffer,
// flushed on its next frame. Set NULL to fall back to the polled queue (return
// 4 from ionPollEvent). type: 1=button, 2=motion, 3=wheel.
//   x,y: position as a FRACTION (0..1) of the surface, top-left origin — the
//        renderer scales by its own resolution (DPI/resize-independent).
//   p1/p2: button=(button,pressed); motion=(relX,relY as surface fractions);
//          wheel=(dx,dy scroll deltas).
typedef void (*IonInputSink)(int type, double x, double y, double p1, double p2);
void  ionRenderSurfaceSetInputSink(IonInputSink sink);

// Composite + lifecycle. All silently no-op when surf is invalid.
void  ionRenderSurfaceSetVisible(IonRenderSurfaceId surf, int visible);
void  ionRenderSurfaceSyncFrame(IonRenderSurfaceId surf);   // match content-view bounds
void  ionRenderSurfaceSetInputRegion(IonRenderSurfaceId surf,
                                     int mode, int x, int y, int w, int h);
void  ionRenderSurfaceRelease(IonRenderSurfaceId surf);     // detach + destroy

// ---- Webview as an element ------------------------------------------------
//
// The webview's frame in device pixels, top-left of the window's client area.
// Until the first call it fills the client area and follows resizes; after it,
// native layout owns the frame. Pointer input inside the frame goes to the
// webview unless an ION_SURFACE_ABOVE surface's input region claims the point.
void  ionWebviewSetFrame(IonWindowId win, int x, int y, int w, int h);
void  ionWebviewSetVisible(IonWindowId win, int visible);

// Pump platform events one tick (SDL+Cocoa on macOS, Win32 PeekMessage on
// Windows). Caller (MS) calls this in a loop; this fn is non-blocking.
// Return codes:
//   0  idle
//   1  quit requested
//   2  IPC message popped — read via ionMessageName / ionMessagePayload
//   3  window lifecycle event — read via ionWindowEventId / ionWindowEventType
//   4  input event — read via ionInputType / ionInputX / ... (render surface)
int  ionPollEvent(void);

// Valid only after ionPollEvent returned 2, until the next ionPollEvent call.
msString    ionMessageName(void);
msString    ionMessagePayload(void);
// Which window the IPC message came from, or ION_WINDOW_INVALID for
// app-global producers (tray, hotkey, notification).
IonWindowId ionMessageWindowId(void);

// Valid only after ionPollEvent returned 3, until the next ionPollEvent call.
// Window lifecycle events. Event types: see ION_EVT_* in common/windowEvents.h.
IonWindowId ionWindowEventId(void);
int         ionWindowEventType(void);

// Valid only after ionPollEvent returned 4 (input event), until the next call.
// A render-surface consumer forwards these into its native renderer's input.
// ionInputSurface is the surface the event belongs to (-1 when the platform
// does not attribute it yet).
//   1 button  x,y = position as a FRACTION (0..1) of the surface, top-left
//             origin (same values the IonInputSink fast path delivers);
//             p1 = button (1=left, 2=right, 3=middle), p2 = pressed (1/0)
//   2 motion  x,y as above; p1,p2 = relX,relY as surface fractions
//   3 wheel   x,y as above; p1,p2 = dx,dy scroll deltas
//   4 key     p1 = ION_KEY_RELEASE/PRESS/REPEAT; key = ION_KEY code (W3C
//             KeyboardEvent.code, name via ionKeyName); scancode = native;
//             mods / consumedMods = ION_MOD_* bits; unshifted = the codepoint
//             the key gives with no modifier (0 when none); text = the UTF-8
//             the press produced (empty for release and for non-text keys)
//   5 text    text = UTF-8 not tied to a key press (IME commit, injected input)
//   6 preedit text = the IME composition in progress (empty = cleared);
//             p1 = caret offset in bytes into text
//   7 focus   p1 = 1 gained / 0 lost
//   8 resize  p1,p2 = surface width,height in device pixels; x = scale (DPI/96)
#define ION_KEY_RELEASE 0
#define ION_KEY_PRESS   1
#define ION_KEY_REPEAT  2

#define ION_MOD_SHIFT       (1 << 0)
#define ION_MOD_CTRL        (1 << 1)
#define ION_MOD_ALT         (1 << 2)
#define ION_MOD_SUPER       (1 << 3)
#define ION_MOD_CAPS_LOCK   (1 << 4)
#define ION_MOD_NUM_LOCK    (1 << 5)
#define ION_MOD_SHIFT_RIGHT (1 << 6)
#define ION_MOD_CTRL_RIGHT  (1 << 7)
#define ION_MOD_ALT_RIGHT   (1 << 8)
#define ION_MOD_SUPER_RIGHT (1 << 9)

int      ionInputType(void);
int      ionInputSurface(void);
double   ionInputX(void);
double   ionInputY(void);
double   ionInputP1(void);
double   ionInputP2(void);
int      ionInputKey(void);
int      ionInputScancode(void);
int      ionInputMods(void);
int      ionInputConsumedMods(void);
int      ionInputUnshifted(void);
msString ionInputText(void);

// W3C KeyboardEvent.code name of an ION_KEY code ("KeyA", "ArrowUp"); "" when
// out of range. The table lives in common/keys.c.
msString ionKeyName(int key);

// MS → JS. Evaluates `js` in the webview's main world.
void ionEvalJS(const char *js);

// Open a native file picker (single file, any type). Returns the selected
// path or "" if the user cancelled. The returned buffer is valid until the
// next ionFileOpen call.
msString ionFileOpen(void);

// Returns the absolute path of the platform's resource directory:
//   macOS:   <bundle>.app/Contents/Resources/
//   Windows: <exe-dir>/resources/
// Returns "" when running in dev mode (no bundle / no resources/ dir next
// to the binary).
msString ionResourcePath(void);

// Toggle content protection on the main window. When on, screen-capture
// frameworks (screenshots, screen recordings, screen sharing) cannot read
// the window's pixels. Useful for windows showing sensitive content.
// `on` non-zero = protect, 0 = allow capture (the default).
void ionSetContentProtected(int on);

// Open `url` in the user's default handler (system browser). Same effect as
// clicking an external link in the webview. No-op on NULL/empty/unparseable
// URL. Used by OAuth loopback flows to launch the provider's consent page.
void ionOpenExternal(const char *url);

// Keychain — secure secret store (macOS only in Phase 4.6; Win/Linux fall
// back to file storage in MS-side wrapper). Items are indexed by
// (service, account). `value` is a UTF-8 string.
//
// Returns:
//   1 — success
//   0 — failure (missing args, Keychain unavailable, permission denied)
//
// ionKeychainGet returns a static buffer valid until the next call to
// ionKeychainGet — same convention as ionFileOpen. Empty string on miss.
int      ionKeychainSet(const char *service, const char *account, const char *value);
msString ionKeychainGet(const char *service, const char *account);
int      ionKeychainDelete(const char *service, const char *account);

// Register a static-mapping URI scheme: <scheme>://localhost/<path> serves
// `<baseDir>/<path>` from disk with auto-detected Content-Type. MUST be
// called BEFORE ionOpen(); subsequent calls after open() return 0.
//
// Returns:
//   1 — registered
//   0 — frozen (open() already called) / duplicate scheme / invalid baseDir
//
// Path-traversal (`..`) blocked. Query string + fragment stripped. URL
// percent-decoded. Empty path → /index.html. See protoreg.{h,c} for details.
int ionRegisterStaticProtocol(const char *scheme, const char *baseDir);

// Register the asset:// scheme with an allowlist of root paths. Requests
// to `asset://localhost/<abs-path>` are served only if `<abs-path>` is
// under one of `allowedRoots` (newline-separated absolute paths). MUST be
// called BEFORE ionOpen().
//
// Returns:
//   1 — registered
//   0 — frozen / already called / invalid input
int ionRegisterAssetScope(const char *allowedRoots);

// Install a menu-bar (tray) status item with the given title text.
// Click → queues a "tray.click" IPC message and brings the main window forward.
void ionInstallTray(const char *title);
// Same as ionInstallTray but uses a template image. The PNG is rendered as
// template (auto dark/light adapt), sized to 18x18. Pass empty path to clear.
void ionInstallTrayImage(const char *pngPath);
void ionUninstallTray(void);

// Post an OS notification. `id` identifies it for the click callback.
// First call requests permission; subsequent calls reuse the granted state.
// Click → queues "notification.click" with payload = id.
void ionNotify(const char *title, const char *body, const char *id);

// Register a global hotkey. modifiers is a bitmask: 1=cmd/win, 2=shift, 4=alt,
// 8=ctrl. keyCode is platform-native:
//   macOS:   Carbon virtual key code (e.g. 37 for 'L')
//   Windows: Win32 virtual-key code (e.g. VK_L = 0x4C)
// MS-side `keyCodeFromName(...)` in src/hotkey.ms returns the right code for
// the build target. `id` distinguishes hotkeys for the unregister/event path.
// Hit → queues "hotkey" with payload = id (as string).
// Returns:
//    1 — registered successfully
//    0 — slot table full (16 hotkeys max)
//   -1 — OS registration failed (combo already taken or invalid keycode)
int  ionRegisterHotkey(int modifiers, int keyCode, int id);
void ionUnregisterHotkey(int id);

// ---- OTA auto-update install (macOS) -------------------------------------
// Builds on a verified .dmg path (download + sha256 + ed25519 already done
// in std/ion update.ms). Stateless: each function takes everything it needs
// and returns its result, so MS-side apply() can interleave progress UI and
// error handling between primitives.
//
//   ionUpdateMountDmg: `hdiutil attach -nobrowse` at a fresh /tmp/ion-mount-
//     <uuid>. Returns the mount-point path on success, "" on failure.
//
//   ionUpdateFindAppInVolume: scan the mount point for the first .app at the
//     volume root. Returns the absolute .app path on success, "" if none.
//
//   ionUpdateReplaceApp: ONE admin auth prompt (AppleScript do-shell-script
//     with administrator privileges) runs /bin/rm -rf <dest> followed by
//     /usr/bin/ditto <src> <dest>. -3 on user cancel; -4 on other error.
//
//   ionUpdateUnmountDmg: hdiutil detach -force.
//
//   ionUpdateRelaunchAndExit: spawn a detached helper shell that polls for
//     the current pid to die and then `open`s the new .app; immediately
//     _exit(0) so the OS releases the running binary lock. Never returns
//     on success.
msString ionUpdateMountDmg(const char *dmgPath);
msString ionUpdateFindAppInVolume(const char *mountPoint);
int      ionUpdateReplaceApp(const char *srcAppPath, const char *destAppPath);
int      ionUpdateUnmountDmg(const char *mountPoint);
int      ionUpdateRelaunchAndExit(const char *destAppPath);

// ---- IPC message contract -------------------------------------------------
//
// When a platform event fires (tray click, notification click, deeplink, etc.)
// the platform layer MUST enqueue an IPC message that MS-side `listen()`
// handlers can pattern-match on. The name + payload shape is part of the
// public contract and identical across platforms — porting a new OS means
// matching this table, not redesigning it.
//
//   name                   payload          fires from
//   ---------------------  ---------------  -------------------------------
//   "ping"                 any              JS code calling window.__ion__.invoke
//   "tray.click"           ""               OS tray icon clicked
//   "notification.click"   <notif-id>       OS notification clicked
//   "hotkey"               <hotkey-id>      global hotkey hit
//   "deeplink"             <url>            URL-scheme handler invoked
//   "console.log"          <message>        webview console.log() (also warn/error/info)
//   "console.warn"         <message>        ↑
//   "console.error"        <message>        ↑
//   "console.info"         <message>        ↑
//   <custom>               <any>            JS code's own window.__ion__.invoke calls
//
// Phase 1 Windows stubs for tray/notify/hotkey do NOT enqueue these messages
// (they're no-ops). Phase 3 + Phase 4 wire the real implementations and MUST
// emit the message names above with the same payload semantics, or MS-side
// listeners written against the mac contract will silently break on Windows.

#endif
