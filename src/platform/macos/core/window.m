// Ion macOS — window lifecycle: create, close, resource path lookup.
//
// SDL3 owns the NSWindow; we extract its handle via a public SDL property
// and attach a WKWebView as a subview of contentView. SDL's window is the
// source of truth — when SDL_DestroyWindow runs, the NSWindow goes too.
//
// Multi-window: every live window owns one IonMacWindowState struct
// (allocated here, stored in the registry slot's platformState field).
// The slot-0 "main" window also mirrors its fields into s_sdlWindow /
// s_nsWindow / s_webview / s_navDelegate so v0 code that reads those
// globals keeps working unchanged.

#import "../state.h"
#import "../../bridge.h"
#import "../internal.h"
#include "../../common/protoReg.h"
#include "../../common/windowRegistry.h"

#include <stdlib.h>
#include <string.h>

static const char kMainLabel[] = "main";

static void teardownWindow(IonMacWindowState *st) {
    if (!st) return;
    if (st->webview) {
        st->webview.navigationDelegate = nil;
        [st->webview removeFromSuperview];
        st->webview = nil;
    }
    st->navDelegate = nil;
    st->nsWindow    = nil;
    if (st->sdlWindow) {
        SDL_DestroyWindow(st->sdlWindow);
        st->sdlWindow = NULL;
    }
}

static void syncMainGlobals(IonMacWindowState *st) {
    if (st) {
        s_sdlWindow   = st->sdlWindow;
        s_nsWindow    = st->nsWindow;
        s_webview     = st->webview;
        s_navDelegate = st->navDelegate;
    } else {
        s_sdlWindow   = NULL;
        s_nsWindow    = nil;
        s_webview     = nil;
        s_navDelegate = nil;
    }
}

IonWindowId ionCreateWindow(const char *label, const char *title,
                            int width, int height, const char *url, int flags) {
    IonWindowId winId = ion_registry_alloc(label);
    if (winId == ION_WINDOW_INVALID) return ION_WINDOW_INVALID;

    // First window in the process freezes the custom-protocol registry —
    // no more registerStaticProtocol / registerAssetScope calls accepted
    // past this point. Subsequent windows don't refreeze.
    if (ion_registry_count() == 1) ionProtoFreeze();

    IonMacWindowState *st = (IonMacWindowState *)calloc(1, sizeof(IonMacWindowState));
    if (!st) {
        ion_registry_free(winId);
        return ION_WINDOW_INVALID;
    }

    NSString *appName = (title && title[0])
        ? [NSString stringWithUTF8String:title]
        : @"ion";

    Uint32 sdlFlags = 0;
    if (flags & ION_WIN_RESIZABLE)     sdlFlags |= SDL_WINDOW_RESIZABLE;
    if (flags & ION_WIN_ALWAYS_ON_TOP) sdlFlags |= SDL_WINDOW_ALWAYS_ON_TOP;
    if (flags & ION_WIN_TRANSPARENT)   sdlFlags |= SDL_WINDOW_TRANSPARENT;
    if (flags & ION_WIN_FULLSCREEN)    sdlFlags |= SDL_WINDOW_FULLSCREEN;
    if (!(flags & ION_WIN_DECORATIONS)) sdlFlags |= SDL_WINDOW_BORDERLESS;
    if (!(flags & ION_WIN_VISIBLE))     sdlFlags |= SDL_WINDOW_HIDDEN;

    st->sdlWindow = SDL_CreateWindow(title ? title : "ion",
                                     width  > 0 ? width  : 1280,
                                     height > 0 ? height : 720,
                                     sdlFlags);
    if (st->sdlWindow == NULL) {
        free(st);
        ion_registry_free(winId);
        return ION_WINDOW_INVALID;
    }

    // Build menu only once (first window). SDL would otherwise set its own
    // main menu each time, clobbering ours.
    if (ion_registry_count() == 1) ionEnsureMenu(appName);

    SDL_PropertiesID props = SDL_GetWindowProperties(st->sdlWindow);
    void *winPtr = SDL_GetPointerProperty(props, SDL_PROP_WINDOW_COCOA_WINDOW_POINTER, NULL);
    if (winPtr == NULL) {
        SDL_DestroyWindow(st->sdlWindow);
        free(st);
        ion_registry_free(winId);
        return ION_WINDOW_INVALID;
    }
    st->nsWindow = (__bridge NSWindow *)winPtr;

    // ionSetupWebview reads s_navDelegate as its delegate slot — temporarily
    // route the "main" globals through this new window so the existing
    // setup code populates s_navDelegate correctly. After setup we copy
    // those values back into the per-window struct.
    SDL_Window *savedSdl   = s_sdlWindow;
    NSWindow   *savedNs    = s_nsWindow;
    WKWebView  *savedWv    = s_webview;
    id          savedNav   = s_navDelegate;

    s_sdlWindow   = st->sdlWindow;
    s_nsWindow    = st->nsWindow;
    s_webview     = nil;
    s_navDelegate = nil;

    st->webview     = ionSetupWebview([st->nsWindow contentView], label);
    st->navDelegate = s_navDelegate;

    // Restore globals — they'll be re-pointed below if this is "main".
    s_sdlWindow   = savedSdl;
    s_nsWindow    = savedNs;
    s_webview     = savedWv;
    s_navDelegate = savedNav;

    if (url != NULL && url[0] != '\0') {
        NSString *urlStr = [NSString stringWithUTF8String:url];
        NSURL *nsURL = [NSURL URLWithString:urlStr];
        if (nsURL != nil) {
            [st->webview loadRequest:[NSURLRequest requestWithURL:nsURL]];
        }
    }

    IonWindowSlot *slot = ion_registry_get(winId);
    slot->platformState = st;

    if (strcmp(label, kMainLabel) == 0) syncMainGlobals(st);

    return winId;
}

void ionCloseWindow(IonWindowId winId) {
    IonWindowSlot *slot = ion_registry_get(winId);
    if (!slot) return;
    IonMacWindowState *st = (IonMacWindowState *)slot->platformState;
    int isMain = (strcmp(slot->label, kMainLabel) == 0);

    teardownWindow(st);
    free(st);
    slot->platformState = NULL;
    ion_registry_free(winId);

    if (isMain) syncMainGlobals(NULL);
}

int ionWindowCount(void) {
    return ion_registry_count();
}

// ---- Legacy single-window API (v0 wrappers) -------------------------------

int ionOpen(const char *title, int width, int height, const char *url) {
    IonWindowId existing = ion_registry_find(kMainLabel);
    if (existing != ION_WINDOW_INVALID) ionCloseWindow(existing);
    return ionCreateWindow(kMainLabel, title, width, height, url, ION_WIN_DEFAULT)
            != ION_WINDOW_INVALID;
}

void ionClose(void) {
    IonWindowId winId = ion_registry_find(kMainLabel);
    if (winId != ION_WINDOW_INVALID) ionCloseWindow(winId);
}

// ---- Bundle resource path --------------------------------------------------

static NSString *s_resourcePath = nil;

msString ionResourcePath(void) {
    if (s_resourcePath == nil) {
        NSString *path = [[NSBundle mainBundle] resourcePath];
        // Unbundled dev binary: NSBundle returns the binary's dir, not a
        // real Resources/. Detect by suffix; fall back to empty.
        s_resourcePath = (path && [path hasSuffix:@"/Contents/Resources"]) ? path : @"";
    }
    return nsStringToMs(s_resourcePath);
}

// ---- Window properties ----------------------------------------------------

void ionShowWindow(IonWindowId winId) {
    IonMacWindowState *st = ionMacWindowState(winId);
    if (st && st->sdlWindow) SDL_ShowWindow(st->sdlWindow);
}

void ionHideWindow(IonWindowId winId) {
    IonMacWindowState *st = ionMacWindowState(winId);
    if (st && st->sdlWindow) SDL_HideWindow(st->sdlWindow);
}

void ionFocusWindow(IonWindowId winId) {
    IonMacWindowState *st = ionMacWindowState(winId);
    if (!st) return;
    if (st->sdlWindow) SDL_RaiseWindow(st->sdlWindow);
    if (st->nsWindow)  [st->nsWindow makeKeyAndOrderFront:nil];
}

void ionMinimizeWindow(IonWindowId winId) {
    IonMacWindowState *st = ionMacWindowState(winId);
    if (st && st->sdlWindow) SDL_MinimizeWindow(st->sdlWindow);
}

void ionMaximizeWindow(IonWindowId winId) {
    IonMacWindowState *st = ionMacWindowState(winId);
    if (st && st->sdlWindow) SDL_MaximizeWindow(st->sdlWindow);
}

void ionSetWindowTitle(IonWindowId winId, const char *title) {
    IonMacWindowState *st = ionMacWindowState(winId);
    if (!st || !st->sdlWindow) return;
    SDL_SetWindowTitle(st->sdlWindow, title ? title : "");
}

void ionSetWindowSize(IonWindowId winId, int width, int height) {
    IonMacWindowState *st = ionMacWindowState(winId);
    if (!st || !st->sdlWindow) return;
    SDL_SetWindowSize(st->sdlWindow, width  > 0 ? width  : 1,
                                     height > 0 ? height : 1);
}

void ionSetWindowPosition(IonWindowId winId, int x, int y) {
    IonMacWindowState *st = ionMacWindowState(winId);
    if (st && st->sdlWindow) SDL_SetWindowPosition(st->sdlWindow, x, y);
}

void ionSetWindowAlwaysOnTop(IonWindowId winId, int on) {
    IonMacWindowState *st = ionMacWindowState(winId);
    if (st && st->sdlWindow) SDL_SetWindowAlwaysOnTop(st->sdlWindow, on ? true : false);
}

void ionSetWindowDecorations(IonWindowId winId, int on) {
    IonMacWindowState *st = ionMacWindowState(winId);
    if (st && st->sdlWindow) SDL_SetWindowBordered(st->sdlWindow, on ? true : false);
}

void ionSetWindowContentProtected(IonWindowId winId, int on) {
    IonMacWindowState *st = ionMacWindowState(winId);
    if (!st || st->nsWindow == nil) return;
    st->nsWindow.sharingType = on ? NSWindowSharingNone : NSWindowSharingReadOnly;
}
