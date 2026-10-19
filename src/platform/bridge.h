// Ion native bridge — public C contract between MS and the platform layer.
//
// Ion is the platform: it owns the OS window, the message pump, the
// compositor root, raw input, the webview engine and OS services. The app
// framework (Neon) builds and drives the content: its own native views and
// Void areas on the window's compositor, and webviews placed wherever its
// tree puts them. Ion does no hit-testing; see "Windows and their content".
//
// Caller (MS) drives the loop via ionPollEvent. Platform callbacks queue
// IPC messages and input records internally; ionPollEvent surfaces them one
// at a time.
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
// 1: this process holds the app's single-instance lock (or the platform gives one
// instance anyway); 0: an earlier process holds it, our cold-start URL was forwarded
// and its window raised. Same answer on every call; opt-in, never taken by ionInit.
int  ionRequestSingleInstance(void);

// ---- Windows and their content -------------------------------------------
//
// A window is an empty native root. The app builds everything inside it on
// the window's compositor: its native views, its Void areas (a visual whose
// content is a swapchain or a layer) and webviews (below). Ion composites
// what the app attaches, delivers the window's raw input as records
// (ionPollEvent returns 4) in device pixels of the client area, and never
// decides which piece of content a point belongs to. When the app's
// hit-test lands on a webview it forwards the event with
// ionWebviewForwardPointer, and it moves keyboard focus with
// ionWebviewFocus / ionWindowFocusContent.
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

// Create an empty window. Returns the window id or ION_WINDOW_INVALID if:
//   - label is NULL/empty/duplicate/over ION_LABEL_MAX
//   - all ION_MAX_WINDOWS slots are taken
//   - native creation failed
IonWindowId ionCreateWindow(const char *label, const char *title,
                            int width, int height, int flags);

// Close a window by id, releasing its webviews. Safe with ION_WINDOW_INVALID.
void        ionCloseWindow(IonWindowId id);

// Number of live windows.
int         ionWindowCount(void);

// Look up a window by label. Returns ION_WINDOW_INVALID if no live window
// has the label. Pure registry lookup — same impl on every platform.
IonWindowId ionFindWindow(const char *label);

// Get the label of a live window, or "" if the id is invalid.
msString    ionWindowLabel(IonWindowId id);

// The compositor the content is built on. NULL for an invalid id.
//   ionWindowDevice  Windows: IDCompositionDevice* created on a D2D device
//                    (DCompositionCreateDevice2), so QueryInterface gives
//                    IDCompositionDevice2 / IDCompositionDesktopDevice and
//                    CreateSurface hands out D2D-drawable surfaces. Every
//                    window returns the same device, so a visual can move
//                    between windows and one commit covers all of them.
//                    macOS, Linux: NULL (the toolkit is the compositor).
//   ionWindowRoot    Windows: the IDCompositionVisual* targeted at the window.
//                    macOS: the window's contentView (NSView*).
//                    Linux: a GtkFixed (GtkWidget*) filling the window.
// Ion adds nothing to the root; the app parents its content and webview
// visuals there or below.
void       *ionWindowDevice(IonWindowId id);
void       *ionWindowRoot(IonWindowId id);

// Commit the app's compositor changes as one transaction. Windows:
// IDCompositionDevice::Commit. macOS, Linux: no-op (the toolkit commits).
void        ionWindowCommit(IonWindowId id);

// Keyboard focus goes back to the app's content (key, text and IME records)
// after a webview held it.
void        ionWindowFocusContent(IonWindowId id);

// Where the IME draws its candidate window while the content has focus: the
// caret rect in device pixels of the client area. Set it whenever the caret
// moves.
void        ionWindowSetImeRect(IonWindowId id, int x, int y, int w, int h);

// Pointer shape over the content (a webview sets its own while the app
// forwards pointer events to it).
#define ION_CURSOR_ARROW    0
#define ION_CURSOR_HAND     1
#define ION_CURSOR_IBEAM    2
#define ION_CURSOR_CROSS    3
#define ION_CURSOR_RESIZE_H 4
#define ION_CURSOR_RESIZE_V 5
void        ionWindowSetCursor(IonWindowId id, int cursor);

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
// 0 if the id is invalid.
int         ionWindowPixelWidth(IonWindowId id);
int         ionWindowPixelHeight(IonWindowId id);

// Per-window file picker. The window param is reserved for future window-
// modal sheet behavior; currently it's application-modal, identical to
// ionFileOpen. Empty string on cancel.
msString    ionFileOpenWindow(IonWindowId id);

// Frame clock, per window. A window asks for frames on demand (one per
// ionWindowRequestFrame) or continuously (every display refresh while it is
// active, or always with ionWindowSetFrameWhenInactive); a minimized or
// hidden window gets none. Each frame is an input record of type 9.
#define ION_FRAME_ON_DEMAND  0
#define ION_FRAME_CONTINUOUS 1

void  ionWindowSetFramePolicy(IonWindowId id, int policy);
void  ionWindowSetFrameWhenInactive(IonWindowId id, int enabled);
void  ionWindowRequestFrame(IonWindowId id);

// ---- Webviews ------------------------------------------------------------
//
// A webview is one element of the app's content: an embedded browser engine
// (WebView2, WKWebView, WebKitGTK) with its own JS runtime that talks to the
// app over Ion's IPC. Ion creates it inside a window and hands out its
// native node; the app parents that node wherever its tree puts it and
// tells Ion the webview's bounds. A webview shows nothing until then.
//
// `label` names the webview for IPC: messages it sends carry its id
// (ionMessageWebviewId), and replies go back to it. Labels are unique per
// process.

typedef int IonWebviewId;
#define ION_WEBVIEW_INVALID (-1)

// Create a webview in `win` that loads `url` once the engine is ready.
// Returns ION_WEBVIEW_INVALID for an unknown window, a missing/duplicate
// label, a full table, or a missing engine (WebView2Loader.dll / runtime).
// The first webview freezes the scheme registry (ionRegisterStaticProtocol,
// ionRegisterAssetScope).
IonWebviewId ionWebviewCreate(IonWindowId win, const char *label, const char *url);

// Close the webview and free its id. Its node is detached from wherever the
// app put it.
void         ionWebviewRelease(IonWebviewId id);

IonWebviewId ionFindWebview(const char *label);
msString     ionWebviewLabel(IonWebviewId id);
IonWindowId  ionWebviewWindow(IonWebviewId id);

// The native node to parent. Windows: IDCompositionVisual* (Ion owns it and
// the browser renders into it). macOS: the WKWebView (NSView*). Linux: the
// WebKitWebView (GtkWidget*).
void        *ionWebviewNode(IonWebviewId id);

// The webview's rect in device pixels of the window's client area. The app
// positions the node in its own tree; Ion needs the absolute rect for the
// engine's size, popups and the IME.
void         ionWebviewSetBounds(IonWebviewId id, int x, int y, int w, int h);
void         ionWebviewSetVisible(IonWebviewId id, int visible);
// Transparent: the page's default background is clear, so content below it
// in the app's tree shows through where the page draws nothing.
void         ionWebviewSetTransparent(IonWebviewId id, int transparent);

void         ionWebviewNavigate(IonWebviewId id, const char *url);
// MS → JS. Evaluates `js` in the webview's main world.
void         ionWebviewEval(IonWebviewId id, const char *js);

// Keyboard focus into the webview; key and text input then reach the page
// directly and produce no input records until ionWindowFocusContent.
void         ionWebviewFocus(IonWebviewId id);

// Forward one pointer event the app's hit-test gave to this webview.
// x,y in device pixels relative to the webview's top-left. button:
// 1 left, 2 right, 3 middle, 4 back, 5 forward (button kinds only).
// delta: wheel notches, positive = away from the user / to the right.
#define ION_POINTER_MOVE    1
#define ION_POINTER_DOWN    2
#define ION_POINTER_UP      3
#define ION_POINTER_WHEEL   4
#define ION_POINTER_HWHEEL  5
#define ION_POINTER_LEAVE   6
void         ionWebviewForwardPointer(IonWebviewId id, int kind, double x, double y,
                                      int button, double delta);

// Pump platform events (SDL+Cocoa on macOS, Win32 on Windows). Caller (MS)
// calls this in a loop. Windows blocks until it has something to return;
// macOS and Linux return 0 after at most 16 ms.
// Return codes:
//   0  idle
//   1  quit requested
//   2  IPC message popped — read via ionMessageName / ionMessagePayload
//   3  window lifecycle event — read via ionWindowEventId / ionWindowEventType
//   4  input record — read via ionInputType / ionInputWindow / ionInputX / ...
//   5  msc's loop has work due (a timer expired or a completion arrived)
//   6  ionWakeLoop was called — run the onWake handlers
int  ionPollEvent(void);

// Call after msRunOnce(0), before ionPollEvent, every turn. Tells the pump
// when msc's loop next needs to run so ionPollEvent can wake for it (Windows:
// a timeout, plus a watcher on msc's completion port; macOS and Linux poll
// every 16 ms and need nothing).
void ionLoopArm(void);

// One record or wake ionPollEvent would return (2, 3, 4 or 6), or 0 when none is ready.
// Never pumps platform messages and never waits. Windows' move/size loop calls it from the
// window proc; macOS and Linux have no such loop and return 0.
int  ionPollReady(void);

// Makes ionPollEvent return 6 once, so the loop thread runs the onWake
// handlers. Callable from any thread, with or without a window; calls made
// before the loop runs them coalesce into one. An idle loop stays asleep
// until it is called.
void ionWakeLoop(void);

// Valid only after ionPollEvent returned 2, until the next ionPollEvent call.
msString     ionMessageName(void);
msString     ionMessagePayload(void);
// Which webview sent the IPC message, or ION_WEBVIEW_INVALID for app-global
// producers (tray, hotkey, notification, deep link).
IonWebviewId ionMessageWebviewId(void);

// Valid only after ionPollEvent returned 3, until the next ionPollEvent call.
// Window lifecycle events. Event types: see ION_EVT_* in common/windowEvents.h.
IonWindowId ionWindowEventId(void);
int         ionWindowEventType(void);

// Valid only after ionPollEvent returned 4 (input record), until the next
// call. Records describe the window's content, never a webview that holds
// keyboard focus. ionInputWindow is the window the record belongs to.
// Pointer coordinates are device pixels, top-left of the client area.
//   1 button  x,y = pointer; p1 = button (1 left, 2 right, 3 middle, 4 back,
//             5 forward), p2 = pressed (1/0)
//   2 motion  x,y = pointer; p1,p2 = movement since the previous pointer
//             record, in device pixels
//   3 wheel   x,y = pointer; p1,p2 = dx,dy in notches (positive = right /
//             away from the user)
//   4 key     p1 = ION_KEY_RELEASE/PRESS/REPEAT; key = ION_KEY code (W3C
//             KeyboardEvent.code, name via ionKeyName); scancode = native;
//             mods / consumedMods = ION_MOD_* bits; unshifted = the codepoint
//             the key gives with no modifier (0 when none); text = the UTF-8
//             the press produced (empty for release and for non-text keys)
//   5 text    text = UTF-8 not tied to a key press (IME commit, injected input)
//   6 preedit text = the IME composition in progress (empty = cleared);
//             p1 = caret offset in bytes into text
//   7 focus   p1 = 1 the content gained keyboard focus / 0 lost it
//   8 resize  p1,p2 = client width,height in device pixels; x = scale (DPI/96)
//   9 frame   x = tick time in ms, monotonic
//  10 leave   the pointer left the client area
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

int         ionInputType(void);
IonWindowId ionInputWindow(void);
double      ionInputX(void);
double      ionInputY(void);
double      ionInputP1(void);
double      ionInputP2(void);
int         ionInputKey(void);
int         ionInputScancode(void);
int         ionInputMods(void);
int         ionInputConsumedMods(void);
int         ionInputUnshifted(void);
msString    ionInputText(void);

// W3C KeyboardEvent.code name of an ION_KEY code ("KeyA", "ArrowUp"); "" when
// out of range. The table lives in common/keys.c.
msString ionKeyName(int key);

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

// Text clipboard, UTF-8. Read returns "" when there is no text or the
// clipboard could not be opened. Write returns 1 on success, 0 on failure.
msString ionClipboardRead(void);
int      ionClipboardWrite(const char *text);

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
// called before the first ionWebviewCreate; later calls return 0.
//
// Returns:
//   1 — registered
//   0 — frozen (a webview exists) / duplicate scheme / invalid baseDir
//
// Path-traversal (`..`) blocked. Query string + fragment stripped. URL
// percent-decoded. Empty path → /index.html. See protoreg.{h,c} for details.
int ionRegisterStaticProtocol(const char *scheme, const char *baseDir);

// Register the asset:// scheme with an allowlist of root paths. Requests
// to `asset://localhost/<abs-path>` are served only if `<abs-path>` is
// under one of `allowedRoots` (newline-separated absolute paths). MUST be
// called before the first ionWebviewCreate.
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

// ---- App menu bar (macos/chrome/menu.m; common/noMenu.c on Windows and Linux) ----
// ionMenuBegin, then ionMenuAddSubmenu before each menu's items, then ionMenuCommit.
#define ION_MENU_UNSUPPORTED  (-1)
#define ION_MENU_UNKNOWN_KEY  (-2)
#define ION_MENU_UNKNOWN_ROLE (-3)

// Mirror MenuRole in menu.ms.
#define ION_MENU_ROLE_ABOUT        0
#define ION_MENU_ROLE_HIDE         1
#define ION_MENU_ROLE_HIDE_OTHERS  2
#define ION_MENU_ROLE_SHOW_ALL     3
#define ION_MENU_ROLE_QUIT         4
#define ION_MENU_ROLE_CLOSE_WINDOW 5
#define ION_MENU_ROLE_MINIMIZE     6
#define ION_MENU_ROLE_ZOOM         7
#define ION_MENU_ROLE_FULLSCREEN   8
#define ION_MENU_ROLE_UNDO         9
#define ION_MENU_ROLE_REDO         10
#define ION_MENU_ROLE_CUT          11
#define ION_MENU_ROLE_COPY         12
#define ION_MENU_ROLE_PASTE        13
#define ION_MENU_ROLE_SELECT_ALL   14
#define ION_MENU_ROLE_RELOAD       15

int ionMenuBegin(void);
int ionMenuAddSubmenu(const char *title);
int ionMenuAddItem(const char *itemId, const char *title, const char *key, int modifiers);
int ionMenuAddRole(int role);
int ionMenuAddSeparator(void);
int ionMenuCommit(void);

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

// ---- Audio (common/audio.c, miniaudio on every platform) -------------------
//
// Ids are >= 0. A negative return is an error: a miniaudio result code or an
// ION_AUDIO_E_* code; ionAudioErrorName turns either into text. Stream and
// recording calls block on the calling (MetaScript) thread, never the device thread.
// ionAudioSoundRate is pitch: speed and pitch move together.

const char *ionAudioErrorName(int code);

int      ionAudioSoundLoad(const char *path);
int      ionAudioSoundUnload(int id);
int      ionAudioSoundPlay(int id);
int      ionAudioSoundPause(int id);
int      ionAudioSoundStop(int id);
int      ionAudioSoundSeek(int id, double ms);
int      ionAudioSoundSetVolume(int id, double volume);
int      ionAudioSoundSetMuted(int id, int muted);
int      ionAudioSoundSetLooping(int id, int looping);
int      ionAudioSoundSetRate(int id, double rate);
int      ionAudioSoundPlaying(int id);
int      ionAudioSoundFinished(int id);   // 1 once after the end, then 0
int      ionAudioSoundLooping(int id);
int      ionAudioSoundMuted(int id);
double   ionAudioSoundVolume(int id);
double   ionAudioSoundRate(int id);
double   ionAudioSoundPositionMs(int id);
double   ionAudioSoundDurationMs(int id);

int      ionAudioOutOpen(int sampleRate, int channels, int bufferFrames);
int      ionAudioOutWrite(int id, const float *samples, int frames);   // interleaved f32; blocks while the ring is full
int      ionAudioOutUnderruns(int id);
int      ionAudioOutClose(int id);
int      ionAudioInOpen(int sampleRate, int channels, int bufferFrames);
int      ionAudioInRead(int id, float *out, int frames);   // blocks until `frames` frames arrive
int      ionAudioInOverruns(int id);
int      ionAudioInClose(int id);

int         ionAudioRecordStart(const char *path, int sampleRate, int channels);   // WAV, 16-bit
int         ionAudioRecordPause(int id);
int         ionAudioRecordResume(int id);
int         ionAudioRecordStop(int id);
int         ionAudioRecordClose(int id);
int         ionAudioRecordRecording(int id);
double      ionAudioRecordDurationMs(int id);
const char *ionAudioRecordPath(int id);

// ---- Media device permission (platform/*/security/mediaAccess.*) -----------
// ionMediaRequest blocks until the user answers: call it from a spawn, never the loop thread.
// A return is ION_MEDIA_GRANTED | DENIED | UNDETERMINED, OR-ed with ION_MEDIA_CAN_ASK, or negative.

#define ION_MEDIA_MICROPHONE    0
#define ION_MEDIA_CAMERA        1

#define ION_MEDIA_GRANTED       0
#define ION_MEDIA_DENIED        1
#define ION_MEDIA_UNDETERMINED  2
#define ION_MEDIA_STATE_MASK    0xff
#define ION_MEDIA_CAN_ASK       0x100

#define ION_MEDIA_E_UNAVAILABLE (-1)   // the OS API could not be reached
#define ION_MEDIA_E_SANDBOX     (-2)   // inside Flatpak: a portal path is not built
#define ION_MEDIA_E_QUERY       (-3)   // the OS API answered with a failure
#define ION_MEDIA_E_KIND        (-4)   // not ION_MEDIA_MICROPHONE or ION_MEDIA_CAMERA

int         ionMediaAccess(int kind);
int         ionMediaRequest(int kind);
const char *ionMediaErrorName(int code);

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
//   ionUpdateReplaceApp: ditto <src> beside <dest>, then swap it in
//     atomically; one admin prompt only when <dest>'s directory is not
//     writable. -2 when the copy fails, -3 on user cancel, -4 when the swap
//     fails (the previous app stays in place).
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
//   "menu.click"           <item-id>        app menu item clicked or its key pressed (macOS)
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
