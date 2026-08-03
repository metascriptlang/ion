// Window lifecycle event queue — small ring buffer, single-threaded FIFO.
//
// Producers: platform event handlers (SDL_EVENT_WINDOW_*, Cocoa nofitications,
// GTK signals, Win32 WM_* messages). Consumer: the poll loop in MS land
// (`ionPollEvent` → returns 3 → MS reads ionWindowEventId/Type).
//
// Kept separate from the IPC queue (queue.c) because the shapes differ:
// IPC carries (name, payload) strings, window events carry (id, eventType)
// integers. Mixing them in one queue would force tagged unions or envelopes.

#ifndef ION_WINDOW_EVENTS_H
#define ION_WINDOW_EVENTS_H

#include "windowRegistry.h"   // IonWindowId

#ifdef __cplusplus
extern "C" {
#endif

// Event types delivered to MS-side handlers. Stable wire — keep in sync
// with src/windowManager.ms WindowEventType enum.
enum {
    ION_EVT_CLOSE_REQUESTED = 1,
    ION_EVT_DESTROYED       = 2,
    ION_EVT_FOCUSED         = 3,
    ION_EVT_BLURRED         = 4,
    ION_EVT_RESIZED         = 5,
    ION_EVT_MOVED           = 6,
};

// Push a (windowId, eventType) pair onto the queue. Drops silently if the
// ring is full (logged to stderr). Returns 0 on success, -1 if dropped.
int  ion_wevt_push(IonWindowId windowId, int eventType);

// Pop the front of the queue into *outId / *outType. Returns 1 if popped,
// 0 if the queue was empty (outputs unchanged).
int  ion_wevt_pop(IonWindowId *outId, int *outType);

#ifdef __cplusplus
}
#endif

#endif
