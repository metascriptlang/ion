// macOS-only globals + ObjC shim around the common IPC queue.

#import "state.h"
#include "../common/queue.h"
#include "../common/windowRegistry.h"

SDL_Window *s_sdlWindow   = NULL;
NSWindow   *s_nsWindow    = nil;
WKWebView  *s_webview     = nil;
id          s_navDelegate = nil;

IonMacWindowState *ionMacWindowState(IonWindowId id) {
    IonWindowSlot *slot = ion_registry_get(id);
    return slot ? (IonMacWindowState *)slot->platformState : NULL;
}

IonMacWindowState *ionMacWindowStateByLabel(const char *label) {
    return ionMacWindowState(ion_registry_find(label));
}

// Reverse lookup: which slot owns this WKWebView? Linear scan; ION_MAX_WINDOWS
// is small (16) so this is fine on the platform message-handler hot path.
static IonWindowId windowIdForWebview(WKWebView *wv) {
    if (wv == nil) return ION_WINDOW_INVALID;
    for (IonWindowId i = ion_registry_next(ION_WINDOW_INVALID);
         i != ION_WINDOW_INVALID;
         i = ion_registry_next(i)) {
        IonMacWindowState *st = ionMacWindowState(i);
        if (st && st->webview == wv) return i;
    }
    return ION_WINDOW_INVALID;
}

void ionEnqueueMessage(NSString *name, NSString *payload) {
    ion_queue_push_w(ION_WINDOW_INVALID,
                     [name UTF8String],
                     payload ? [payload UTF8String] : "");
}

void ionEnqueueMessageFrom(WKWebView *srcWebview, NSString *name, NSString *payload) {
    ion_queue_push_w(windowIdForWebview(srcWebview),
                     [name UTF8String],
                     payload ? [payload UTF8String] : "");
}
