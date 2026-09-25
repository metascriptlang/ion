// Ion macOS — event pump + IPC + window-lifecycle accessors.
//
// Priority order each tick:
//   1. drain a queued window-lifecycle event  → return 3
//   2. drain a queued IPC message              → return 2
//   3. wait up to 16ms for an SDL event (which also pumps Cocoa run loop,
//      letting WKScriptMessageHandler + URL handler enqueue while we wait);
//      classify SDL_EVENT_WINDOW_* → push to wevt queue
//   4. drain wevt + IPC again — events that arrived during wait
//   5. otherwise → return 0 (idle)
//
// Quit (Cmd+Q via SDL_EVENT_QUIT, or close button on the "main" window in
// legacy mode) → return 1. Step 4 will transition close-requested to
// ION_EVT_CLOSE_REQUESTED with MS-side default close.

#import "../state.h"
#import "../../bridge.h"
#import "../internal.h"
#include "../../common/queue.h"
#include "../../common/windowEvents.h"
#include "../../common/windowRegistry.h"
#include "../../common/inputEvents.h"

static IonWindowId s_last_wevt_id   = ION_WINDOW_INVALID;
static int         s_last_wevt_type = 0;

static IonWindowId windowIdForSdlWindowId(SDL_WindowID sdlWindowId) {
    SDL_Window *w = SDL_GetWindowFromID(sdlWindowId);
    if (w == NULL) return ION_WINDOW_INVALID;
    for (IonWindowId i = ion_registry_next(ION_WINDOW_INVALID);
         i != ION_WINDOW_INVALID;
         i = ion_registry_next(i)) {
        IonMacWindowState *st = ionMacWindowState(i);
        if (st && st->sdlWindow == w) return i;
    }
    return ION_WINDOW_INVALID;
}

int ionPollEvent(void) {
    if (ion_wevt_pop(&s_last_wevt_id, &s_last_wevt_type)) return 3;
    if (ion_queue_pop()) return 2;
    if (ion_input_next()) return 4;

    SDL_Event ev;
    int got = SDL_WaitEventTimeout(&ev, 16);
    if (got) {
        if (ev.type == SDL_EVENT_QUIT) return 1;
        if (ev.type == SDL_EVENT_WINDOW_CLOSE_REQUESTED) return 1;

        IonWindowId wid;
        switch (ev.type) {
            case SDL_EVENT_WINDOW_FOCUS_GAINED:
                wid = windowIdForSdlWindowId(ev.window.windowID);
                if (wid != ION_WINDOW_INVALID) ion_wevt_push(wid, ION_EVT_FOCUSED);
                break;
            case SDL_EVENT_WINDOW_FOCUS_LOST:
                wid = windowIdForSdlWindowId(ev.window.windowID);
                if (wid != ION_WINDOW_INVALID) ion_wevt_push(wid, ION_EVT_BLURRED);
                break;
            case SDL_EVENT_WINDOW_RESIZED:
                wid = windowIdForSdlWindowId(ev.window.windowID);
                if (wid != ION_WINDOW_INVALID) ion_wevt_push(wid, ION_EVT_RESIZED);
                break;
            case SDL_EVENT_WINDOW_MOVED:
                wid = windowIdForSdlWindowId(ev.window.windowID);
                if (wid != ION_WINDOW_INVALID) ion_wevt_push(wid, ION_EVT_MOVED);
                break;
            default:
                break;
        }
    }

    // Mouse events captured by the surface host view during the Cocoa pump above.
    if (ion_input_next()) return 4;

    if (ion_wevt_pop(&s_last_wevt_id, &s_last_wevt_type)) return 3;
    if (ion_queue_pop()) return 2;
    return 0;
}

msString    ionMessageName(void)     { return cStringToMs(ion_queue_last_name()); }
msString    ionMessagePayload(void)  { return cStringToMs(ion_queue_last_payload()); }
IonWindowId ionMessageWindowId(void) { return ion_queue_last_window_id(); }

IonWindowId ionWindowEventId(void)   { return s_last_wevt_id; }
int         ionWindowEventType(void) { return s_last_wevt_type; }

int ionWindowPixelWidth(IonWindowId id) {
    IonMacWindowState *st = ionMacWindowState(id);
    if (!st || st->sdlWindow == NULL) return 0;
    int w = 0, h = 0;
    SDL_GetWindowSizeInPixels(st->sdlWindow, &w, &h);
    return w;
}

int ionWindowPixelHeight(IonWindowId id) {
    IonMacWindowState *st = ionMacWindowState(id);
    if (!st || st->sdlWindow == NULL) return 0;
    int w = 0, h = 0;
    SDL_GetWindowSizeInPixels(st->sdlWindow, &w, &h);
    return h;
}
