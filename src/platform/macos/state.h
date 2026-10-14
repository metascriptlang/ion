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

typedef struct {
    SDL_Window *sdlWindow;
    NSWindow   *nsWindow;
    NSView     *host;      // IonContentHost: the window's input and focus target
} IonMacWindowState;

typedef struct {
    WKWebView *view;
    id         navDelegate;   // strong ref; Cocoa holds the delegate weakly
} IonMacWebviewState;

IonMacWindowState *ionMacWindowState(IonWindowId id);
IonMacWindowState *ionMacWindowStateByLabel(const char *label);
IonMacWebviewState *ionMacWebviewState(int webview);

extern SDL_Window *s_sdlWindow;
extern NSWindow   *s_nsWindow;

void ionEnqueueMessage(NSString *name, NSString *payload);
void ionEnqueueMessageFrom(int webview, NSString *name, NSString *payload);

#endif
