// Ion macOS — shared state + helper declarations.
//
// All static globals live in state.m. Other implementation files reference
// them via these extern declarations. Keeping state in one place makes
// lifecycle reasoning straightforward; helper functions encapsulate the
// few state mutations that have invariants (queue, invoke_key).

#ifndef ION_MACOS_STATE_H
#define ION_MACOS_STATE_H

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <SDL3/SDL.h>

#include "../common/windowRegistry.h"

// ---- Per-window state -----------------------------------------------------
//
// One IonMacWindowState struct per live window. The address is stored in
// the slot's `platformState` field (see common/windowRegistry.h). Lifetime
// is owned by core/window.m: allocated in ionCreateWindow, freed in
// ionCloseWindow after native teardown.
typedef struct {
    SDL_Window *sdlWindow;
    NSWindow   *nsWindow;
    WKWebView  *webview;
    id          navDelegate;   // strong ref; Cocoa holds the delegate weakly
} IonMacWindowState;

// Look up the state struct for a window id. Returns NULL for invalid/closed.
IonMacWindowState *ionMacWindowState(IonWindowId id);

// Look up the state struct by label. Returns NULL if no slot has the label.
IonMacWindowState *ionMacWindowStateByLabel(const char *label);

// ---- Backward-compat globals ----------------------------------------------
//
// Mirror the "main" window's state for v0 code that hasn't migrated to the
// per-window struct yet. These point to fields inside the slot-0
// IonMacWindowState when a "main" window is open, and NULL/nil otherwise.
//
// Existing macOS .m files (eval.m, nav_delegate.m, chrome/*, security/*)
// keep using these globals and implicitly target the "main" window — that's
// the v0 behavior. Multi-window code paths use ionMacWindowState(id).

extern SDL_Window *s_sdlWindow;
extern NSWindow   *s_nsWindow;
extern WKWebView  *s_webview;
extern id          s_navDelegate;

// ---- ObjC convenience wrapper around the common queue ---------------------

// Thin shim: NSString → const char * → ion_queue_push_w. Lets ObjC callers
// avoid manual UTF8String conversions at every call site. Tags the message
// with the source window's id (looked up from `srcWebview`; falls back to
// ION_WINDOW_INVALID for app-global producers like tray/hotkey).
void ionEnqueueMessage(NSString *name, NSString *payload);
void ionEnqueueMessageFrom(WKWebView *srcWebview, NSString *name, NSString *payload);

#endif
