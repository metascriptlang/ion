// Ion macOS — window lifecycle: create, close, resource path lookup.


#import "../state.h"
#import "../../bridge.h"
#import "../internal.h"
#include "../../common/frameClock.h"
#include "../../common/windowEvents.h"
#include "../../common/webviewRegistry.h"
#include "../../common/windowRegistry.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// NSPanel without a title bar does not become key unless asked (Ghostty QuickTerminalWindow).
@interface IonPanel : NSPanel
@end

@implementation IonPanel
- (BOOL)canBecomeKeyWindow  { return YES; }
- (BOOL)canBecomeMainWindow { return YES; }
@end

static const char kMainLabel[] = "main";
static int s_hadWindow;

static void teardownWindow(IonMacWindowState *st) {
    if (!st) return;
    if (st->host) {
        ionMacFrameDetach(st->host);
        ionContentHostDestroy(st->host);
        st->host = nil;
    }
    st->nsWindow = nil;
    if (st->sdlWindow) {
        SDL_DestroyWindow(st->sdlWindow);
        st->sdlWindow = NULL;
    }
    // SDL leaves a window it wrapped open (SDL_WINDOW_EXTERNAL).
    [st->panel close];
    st->panel = nil;
}

// Electron's ElectronNSPanel and Ghostty's QuickTerminalWindow: a non-activating panel at the
// floating level that joins every Space, a fullscreen one too; SDL wraps it.
static SDL_Window *createPanel(IonMacWindowState *st, const char *title, int width, int height, int flags, Uint32 sdlFlags) {
    NSWindowStyleMask style = NSWindowStyleMaskNonactivatingPanel;
    if (flags & ION_WIN_DECORATIONS) style |= NSWindowStyleMaskTitled | NSWindowStyleMaskClosable;
    if (flags & ION_WIN_RESIZABLE)   style |= NSWindowStyleMaskResizable;
    IonPanel *panel = [[IonPanel alloc] initWithContentRect:NSMakeRect(0, 0, width, height)
                                                  styleMask:style
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
    panel.floatingPanel = YES;
    panel.hidesOnDeactivate = NO;
    panel.releasedWhenClosed = NO;
    panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
    if (title) panel.title = [NSString stringWithUTF8String:title] ?: @"";
    [panel center];
    SDL_PropertiesID props = SDL_CreateProperties();
    SDL_SetPointerProperty(props, SDL_PROP_WINDOW_CREATE_COCOA_WINDOW_POINTER, (__bridge void *)panel);
    SDL_SetNumberProperty(props, SDL_PROP_WINDOW_CREATE_FLAGS_NUMBER, sdlFlags);
    SDL_Window *window = SDL_CreateWindowWithProperties(props);
    SDL_DestroyProperties(props);
    if (window != NULL) st->panel = panel;
    return window;
}

static void syncMainGlobals(IonMacWindowState *st) {
    s_sdlWindow = st ? st->sdlWindow : NULL;
    s_nsWindow  = st ? st->nsWindow : nil;
}

IonWindowId ionCreateWindow(const char *label, const char *title,
                            int width, int height, int flags) {
    IonWindowId winId = ion_registry_alloc(label);
    if (winId == ION_WINDOW_INVALID) return ION_WINDOW_INVALID;

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

    st->sdlWindow = (flags & ION_WIN_PANEL)
        ? createPanel(st, title, width > 0 ? width : 1280, height > 0 ? height : 720, flags, sdlFlags)
        : SDL_CreateWindow(title ? title : "ion",
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
    if (!s_hadWindow) ionEnsureMenu(appName);

    SDL_PropertiesID props = SDL_GetWindowProperties(st->sdlWindow);
    void *winPtr = SDL_GetPointerProperty(props, SDL_PROP_WINDOW_COCOA_WINDOW_POINTER, NULL);
    if (winPtr == NULL) {
        SDL_DestroyWindow(st->sdlWindow);
        free(st);
        ion_registry_free(winId);
        return ION_WINDOW_INVALID;
    }
    st->nsWindow = (__bridge NSWindow *)winPtr;
    st->nsWindow.acceptsMouseMovedEvents = YES;
    st->host = ionContentHostCreate(winId, st->nsWindow);

    IonWindowSlot *slot = ion_registry_get(winId);
    slot->platformState = st;
    ion_frame_window_open(winId);
    ionSyncFrameState(winId);
    s_hadWindow = 1;

    if (strcmp(label, kMainLabel) == 0) syncMainGlobals(st);

    return winId;
}

void ionCloseWindow(IonWindowId winId) {
    IonWindowSlot *slot = ion_registry_get(winId);
    if (!slot || !slot->platformState) return;
    IonMacWindowState *st = (IonMacWindowState *)slot->platformState;
    int isMain = (strcmp(slot->label, kMainLabel) == 0);

    for (int wv = ion_webview_next(-1); wv != ION_WEBVIEW_INVALID; wv = ion_webview_next(wv)) {
        if (ion_webview_get(wv)->window == winId) ionWebviewRelease(wv);
    }

    ion_frame_window_close(winId);
    teardownWindow(st);
    free(st);
    slot->platformState = NULL;
    ion_wevt_push(winId, ION_EVT_DESTROYED);

    if (isMain) syncMainGlobals(NULL);
}

// A destroyed window's registry slot stays until the loop has read its DESTROYED event,
// so the label lookup for that event still resolves.
void ionMacReleaseDestroyed(IonWindowId winId) {
    IonWindowSlot *slot = ion_registry_get(winId);
    if (slot && !slot->platformState) ion_registry_free(winId);
}

int ionMacAllWindowsClosed(void) {
    return s_hadWindow && ionWindowCount() == 0;
}

int ionWindowCount(void) {
    int n = 0;
    for (IonWindowId i = ion_registry_next(ION_WINDOW_INVALID); i != ION_WINDOW_INVALID; i = ion_registry_next(i)) {
        if (ionMacWindowState(i)) n++;
    }
    return n;
}

void ionSyncFrameState(IonWindowId winId) {
    IonMacWindowState *st = ionMacWindowState(winId);
    if (!st || !st->sdlWindow) return;
    SDL_WindowFlags f = SDL_GetWindowFlags(st->sdlWindow);
    int visible = !(f & (SDL_WINDOW_HIDDEN | SDL_WINDOW_MINIMIZED | SDL_WINDOW_OCCLUDED));
    ion_frame_window_state(winId, (f & SDL_WINDOW_INPUT_FOCUS) != 0, visible);
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

void *ionWindowDevice(IonWindowId winId) {
    (void)winId;
    return NULL;
}

void *ionWindowRoot(IonWindowId winId) {
    IonMacWindowState *st = ionMacWindowState(winId);
    return st && st->nsWindow ? (__bridge void *)[st->nsWindow contentView] : NULL;
}

void ionWindowCommit(IonWindowId winId) {
    (void)winId;
}

void ionWindowFocusContent(IonWindowId winId) {
    IonMacWindowState *st = ionMacWindowState(winId);
    if (st && st->host) [st->nsWindow makeFirstResponder:st->host];
}

void ionWindowSetImeRect(IonWindowId winId, int x, int y, int w, int h) {
    IonMacWindowState *st = ionMacWindowState(winId);
    if (st && st->host) ionContentHostSetImeRect(st->host, x, y, w, h);
}

void ionWindowSetCursor(IonWindowId winId, int cursor) {
    IonMacWindowState *st = ionMacWindowState(winId);
    if (st && st->host) ionContentHostSetCursor(st->host, cursor);
}

void ionWindowSetOptionAsAlt(IonWindowId winId, int sides) {
    IonMacWindowState *st = ionMacWindowState(winId);
    if (st && st->host) ionContentHostSetOptionAsAlt(st->host, sides);
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
    // A panel takes the keys and leaves the app inactive (Electron NativeWindowMac::Focus).
    if (st->panel) {
        [st->panel makeKeyAndOrderFront:nil];
        return;
    }
    if (st->sdlWindow) SDL_RaiseWindow(st->sdlWindow);
    if (st->nsWindow)  [st->nsWindow makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
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
    if (SDL_GetWindowFlags(st->sdlWindow) & SDL_WINDOW_MAXIMIZED) SDL_RestoreWindow(st->sdlWindow);
    SDL_SetWindowSize(st->sdlWindow, width  > 0 ? width  : 1,
                                     height > 0 ? height : 1);
}

void ionSetWindowPosition(IonWindowId winId, int x, int y) {
    IonMacWindowState *st = ionMacWindowState(winId);
    if (!st || st->nsWindow == nil) return;
    CGFloat top = NSScreen.screens[0].frame.size.height - y;
    [st->nsWindow setFrameTopLeftPoint:NSMakePoint(x, top)];
}

void ionSetWindowAlwaysOnTop(IonWindowId winId, int on) {
    IonMacWindowState *st = ionMacWindowState(winId);
    if (st && st->sdlWindow) SDL_SetWindowAlwaysOnTop(st->sdlWindow, on ? true : false);
}

void ionWindowRequestUserAttention(IonWindowId winId, int type) {
    if (ionMacWindowState(winId) == NULL || type == ION_ATTENTION_NONE) return;
    [NSApp requestUserAttention:type == ION_ATTENTION_CRITICAL ? NSCriticalRequest : NSInformationalRequest];
}

void ionBeep(void) {
    NSBeep();
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
