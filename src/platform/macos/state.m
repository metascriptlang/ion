// macOS-only globals + ObjC shim around the common IPC queue.

#import "state.h"
#include "../common/queue.h"
#include "../common/webviewRegistry.h"
#include "../common/windowRegistry.h"

SDL_Window *s_sdlWindow = NULL;
NSWindow   *s_nsWindow  = nil;

IonMacWindowState *ionMacWindowState(IonWindowId id) {
    IonWindowSlot *slot = ion_registry_get(id);
    return slot ? (IonMacWindowState *)slot->platformState : NULL;
}

IonMacWindowState *ionMacWindowStateByLabel(const char *label) {
    return ionMacWindowState(ion_registry_find(label));
}

IonMacWebviewState *ionMacWebviewState(int webview) {
    IonWebviewSlot *slot = ion_webview_get(webview);
    return slot ? (IonMacWebviewState *)slot->platformState : NULL;
}

void ionEnqueueMessage(NSString *name, NSString *payload) {
    ionEnqueueMessageFrom(-1, name, payload);
}

void ionEnqueueMessageFrom(int webview, NSString *name, NSString *payload) {
    ion_queue_push_w(webview, [name UTF8String], payload ? [payload UTF8String] : "");
}
