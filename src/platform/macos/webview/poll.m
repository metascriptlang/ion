// Ion macOS — event pump + IPC + window-lifecycle accessors.
//
// Priority order each tick:
//   1. drain a queued window-lifecycle event  → return 3
//   2. drain a queued IPC message              → return 2
//   3. wait up to 16ms for an SDL event (which also pumps Cocoa run loop,
//      letting WKScriptMessageHandler + URL handler enqueue while we wait);
//      classify SDL_EVENT_WINDOW_* → push to wevt queue
//   4. drain wevt + IPC again — events that arrived during wait
//   5. frame records for windows due one → return 4
//   6. otherwise → return 0 (idle)
//
// A title-bar close pushes close-requested, then destroys that window (destroyed follows).
// Quit (Cmd+Q, or SDL_EVENT_QUIT after the last close) and the last window gone → return 1,
// once the queued lifecycle events have been delivered.

#import "../state.h"
#import "../../bridge.h"
#import "../internal.h"
#include "../../common/queue.h"
#include "../../common/windowEvents.h"
#include "../../common/windowRegistry.h"
#include "../../common/inputEvents.h"
#include "../../common/frameClock.h"

#include <stdatomic.h>

static IonWindowId s_last_wevt_id   = ION_WINDOW_INVALID;
static int         s_last_wevt_type = 0;
static int         s_quit = 0;
static atomic_int  s_wakePending;

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

// Wakes coalesce into one pending flag, as on Linux, so a flood from another thread posts one
// SDL event per loop turn instead of filling SDL's queue.
void ionWakeLoop(void) {
    if (atomic_exchange(&s_wakePending, 1)) return;
    SDL_Event ev;
    SDL_zero(ev);
    ev.type = SDL_EVENT_USER;
    if (!SDL_PushEvent(&ev)) {
        fprintf(stderr, "[ion] ionWakeLoop: SDL_PushEvent failed: %s\n", SDL_GetError());
        abort();
    }
}

int ionPollEvent(void) {
    if (s_last_wevt_type == ION_EVT_DESTROYED) {
        ionMacReleaseDestroyed(s_last_wevt_id);
        s_last_wevt_type = 0;
    }
    if (ion_wevt_pop(&s_last_wevt_id, &s_last_wevt_type)) return 3;
    if (ion_queue_pop()) return 2;
    if (ion_input_next()) return 4;
    if (s_quit || ionMacAllWindowsClosed()) return 1;

    SDL_Event ev;
    int got = SDL_WaitEventTimeout(&ev, 16);
    if (got) {
        if (ev.type == SDL_EVENT_USER && atomic_exchange(&s_wakePending, 0)) return 6;
        if (ev.type == SDL_EVENT_QUIT) s_quit = 1;

        IonWindowId wid;
        switch (ev.type) {
            case SDL_EVENT_WINDOW_FOCUS_GAINED:
                wid = windowIdForSdlWindowId(ev.window.windowID);
                if (wid != ION_WINDOW_INVALID) {
                    ion_wevt_push(wid, ION_EVT_FOCUSED);
                    ionSyncFrameState(wid);
                }
                break;
            case SDL_EVENT_WINDOW_FOCUS_LOST:
                wid = windowIdForSdlWindowId(ev.window.windowID);
                if (wid != ION_WINDOW_INVALID) {
                    ion_wevt_push(wid, ION_EVT_BLURRED);
                    ionSyncFrameState(wid);
                }
                break;
            case SDL_EVENT_WINDOW_MINIMIZED:
            case SDL_EVENT_WINDOW_RESTORED:
            case SDL_EVENT_WINDOW_HIDDEN:
            case SDL_EVENT_WINDOW_SHOWN:
                wid = windowIdForSdlWindowId(ev.window.windowID);
                if (wid != ION_WINDOW_INVALID) ionSyncFrameState(wid);
                break;
            case SDL_EVENT_WINDOW_CLOSE_REQUESTED:
                wid = windowIdForSdlWindowId(ev.window.windowID);
                if (wid != ION_WINDOW_INVALID) {
                    ion_wevt_push(wid, ION_EVT_CLOSE_REQUESTED);
                    ionCloseWindow(wid);
                }
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

    if (ion_input_next()) return 4;

    if (ion_wevt_pop(&s_last_wevt_id, &s_last_wevt_type)) return 3;
    if (ion_queue_pop()) return 2;
    if (ion_frame_emit((double)SDL_GetTicksNS() / 1e6) > 0 && ion_input_next()) return 4;
    return 0;
}

msString    ionMessageName(void)     { return cStringToMs(ion_queue_last_name()); }
msString    ionMessagePayload(void)  { return cStringToMs(ion_queue_last_payload()); }

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

void ionLoopArm(void) {}
