// Ion macOS — event pump + IPC + window-lifecycle accessors.
//
// Priority order each turn:
//   1. drain a queued window-lifecycle event  → return 3
//   2. drain a queued IPC message              → return 2
//   3. wait in Cocoa until an NSEvent is queued or msc's next timer is due, then pump SDL
//      and classify SDL_EVENT_WINDOW_* → push to wevt queue
//   4. drain input, wevt and IPC again — events that arrived during the wait
//   5. frame records for windows due one, on the vsync tick (core/frame.m) → return 4
//   6. a coalesced ionWakeLoop → return 6
//   7. msc has work (its kqueue turned readable, or a timer is due) → return 5
//
// The wait is Ion's own, as MsgWaitForMultipleObjectsEx is on Windows: SDL_WaitEventTimeout
// returns only once an SDL event is queued, and only while a window exists to wake it
// (SDL_events.c SDL_WaitEventTimeoutNS), but Ion's producers (WKScriptMessageHandler,
// IonContentHost input, deep links, hotkeys, tray, notifications, the display link) run on
// the main run loop without one. Each of them, every other thread, and an SDL event watch call
// ionMacNudge.
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
#include "../../common/mscLoop.h"
#include "runtime/promise/dispatch.h"

#include <errno.h>
#include <string.h>
#include <pthread.h>
#include <signal.h>
#include <stdatomic.h>
#include <sys/event.h>
#include <unistd.h>

static IonWindowId s_last_wevt_id   = ION_WINDOW_INVALID;
static int         s_last_wevt_type = 0;
static int         s_quit = 0;
static atomic_int  s_wakePending;
static atomic_int  s_nudgePending;

static atomic_int      s_mscReady;
static int             s_mscTimed;
static Uint64          s_mscDeadline;
static int             s_mscDrained;
static pthread_mutex_t s_mscLock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t  s_mscCond = PTHREAD_COND_INITIALIZER;

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

// Nudges coalesce into one queued NSEvent per loop turn, so a flood from another thread does
// not fill the event queue. postEvent:atStart: is safe off the main thread. The loop clears
// the flag only after its pump, and reads every source after that: a nudge posted during the
// pump is dequeued by it, and a flag cleared before the pump would then wait on nothing.
static void postNudge(void) {
    @autoreleasepool {
        NSEvent *ev = [NSEvent otherEventWithType:NSEventTypeApplicationDefined
                                         location:NSZeroPoint
                                    modifierFlags:0
                                        timestamp:0
                                     windowNumber:0
                                          context:nil
                                          subtype:0
                                            data1:0
                                            data2:0];
        [NSApp postEvent:ev atStart:NO];
    }
}

void ionMacNudge(void) {
    if (atomic_exchange(&s_nudgePending, 1)) return;
    postNudge();
}

void ionWakeLoop(void) {
    if (atomic_exchange(&s_wakePending, 1)) return;
    ionMacNudge();
}

// Electron's NodeBindingsMac shape, the twin of the IOCP watcher in windows/webview/poll.c:
// a thread watches msc's kqueue from a kqueue of its own (a kqueue descriptor turns readable
// while events are pending, without consuming them), nudges the loop, and parks until
// ionLoopArm has run msc, so it does not spin on the events still pending.
// SDL's SIGINT/SIGTERM handler only sets a flag that the next pump turns into SDL_EVENT_QUIT
// (SDL_quit.c SDL_HandleSIG), so the same kqueue records those signals, without taking them
// from the handler, and posts a pump. kevent reports a signal as it is sent, possibly before
// the handler has run, and a coalesced nudge may already be spent, so the post waits 10 ms
// and is not coalesced; signals are too rare to flood the queue.
static void *mscWatcher(void *arg) {
    int mscFd = (int)(intptr_t)arg;
    int kq = kqueue();
    struct kevent changes[3];
    EV_SET(&changes[0], mscFd, EVFILT_READ, EV_ADD, 0, 0, NULL);
    EV_SET(&changes[1], SIGINT, EVFILT_SIGNAL, EV_ADD, 0, 0, NULL);
    EV_SET(&changes[2], SIGTERM, EVFILT_SIGNAL, EV_ADD, 0, 0, NULL);
    if (kq < 0 || kevent(kq, changes, 3, NULL, 0, NULL) < 0) {
        fprintf(stderr, "[ion] msc watcher: cannot watch msc's kqueue: %s\n", strerror(errno));
        abort();
    }
    for (;;) {
        struct kevent ready;
        int n = kevent(kq, NULL, 0, &ready, 1, NULL);
        if (n < 0) {
            if (errno == EINTR) continue;
            fprintf(stderr, "[ion] msc watcher: kevent failed: %s\n", strerror(errno));
            abort();
        }
        if (ready.filter == EVFILT_SIGNAL) {
            usleep(10000);
            postNudge();
            continue;
        }
        pthread_mutex_lock(&s_mscLock);
        s_mscDrained = 0;
        pthread_mutex_unlock(&s_mscLock);
        atomic_store(&s_mscReady, 1);
        ionMacNudge();
        pthread_mutex_lock(&s_mscLock);
        while (!s_mscDrained) pthread_cond_wait(&s_mscCond, &s_mscLock);
        pthread_mutex_unlock(&s_mscLock);
    }
    return NULL;
}

// SDL queues events of its own without an NSEvent to end the wait: SDL_EVENT_QUIT from
// applicationShouldTerminate (an AppleScript quit), display and device changes. A watch runs
// on every push, from whichever thread pushes.
static bool nudgeOnSdlEvent(void *userdata, SDL_Event *event) {
    (void)userdata; (void)event;
    ionMacNudge();
    return true;
}

static void startWatcher(void) {
    static int started;
    if (started) return;
    started = 1;
    if (!SDL_AddEventWatch(nudgeOnSdlEvent, NULL)) {
        fprintf(stderr, "[ion] SDL_AddEventWatch failed: %s\n", SDL_GetError());
        abort();
    }
    msGetDispatcher();
    int fd = msGetDispatcherSelectorFd();
    pthread_t thread;
    if (fd < 0 || pthread_create(&thread, NULL, mscWatcher, (void *)(intptr_t)fd) != 0) {
        fprintf(stderr, "[ion] msc watcher: start failed (selector fd %d)\n", fd);
        abort();
    }
    pthread_detach(thread);
}

void ionLoopArm(void) {
    startWatcher();
    int delay = ion_msc_next_delay_ms();
    s_mscTimed = delay >= 0;
    if (s_mscTimed) s_mscDeadline = SDL_GetTicks() + (Uint64)delay;
    pthread_mutex_lock(&s_mscLock);
    s_mscDrained = 1;
    pthread_cond_signal(&s_mscCond);
    pthread_mutex_unlock(&s_mscLock);
}

static int mscDue(void) {
    return atomic_load(&s_mscReady) || (s_mscTimed && SDL_GetTicks() >= s_mscDeadline);
}

static void waitForEvent(void) {
    NSDate *until = NSDate.distantFuture;
    if (mscDue() || atomic_load(&s_wakePending) || ionMacFrameTickPending()) {
        until = NSDate.distantPast;
    } else if (s_mscTimed) {
        until = [NSDate dateWithTimeIntervalSinceNow:(double)(s_mscDeadline - SDL_GetTicks()) / 1000.0];
    }
    [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:until inMode:NSDefaultRunLoopMode dequeue:NO];
}

static void handleSdlEvent(const SDL_Event *ev) {
    if (ev->type == SDL_EVENT_QUIT) s_quit = 1;

    IonWindowId wid;
    switch (ev->type) {
        case SDL_EVENT_WINDOW_FOCUS_GAINED:
            wid = windowIdForSdlWindowId(ev->window.windowID);
            if (wid != ION_WINDOW_INVALID) {
                ion_wevt_push(wid, ION_EVT_FOCUSED);
                ionSyncFrameState(wid);
            }
            break;
        case SDL_EVENT_WINDOW_FOCUS_LOST:
            wid = windowIdForSdlWindowId(ev->window.windowID);
            if (wid != ION_WINDOW_INVALID) {
                ion_wevt_push(wid, ION_EVT_BLURRED);
                ionSyncFrameState(wid);
            }
            break;
        case SDL_EVENT_WINDOW_MINIMIZED:
        case SDL_EVENT_WINDOW_RESTORED:
        case SDL_EVENT_WINDOW_HIDDEN:
        case SDL_EVENT_WINDOW_SHOWN:
        case SDL_EVENT_WINDOW_OCCLUDED:
        case SDL_EVENT_WINDOW_EXPOSED:
            wid = windowIdForSdlWindowId(ev->window.windowID);
            if (wid != ION_WINDOW_INVALID) ionSyncFrameState(wid);
            break;
        case SDL_EVENT_WINDOW_CLOSE_REQUESTED:
            wid = windowIdForSdlWindowId(ev->window.windowID);
            if (wid != ION_WINDOW_INVALID) {
                ion_wevt_push(wid, ION_EVT_CLOSE_REQUESTED);
                ionCloseWindow(wid);
            }
            break;
        case SDL_EVENT_WINDOW_RESIZED:
            wid = windowIdForSdlWindowId(ev->window.windowID);
            if (wid != ION_WINDOW_INVALID) ion_wevt_push(wid, ION_EVT_RESIZED);
            break;
        case SDL_EVENT_WINDOW_MOVED:
            wid = windowIdForSdlWindowId(ev->window.windowID);
            if (wid != ION_WINDOW_INVALID) ion_wevt_push(wid, ION_EVT_MOVED);
            break;
        default:
            break;
    }
}

static int emitDueFrames(void) {
    double timeMs;
    return ionMacFrameTakeTick(&timeMs) && ion_frame_emit(timeMs) > 0 && ion_input_next();
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

    // The run loop is pumped every turn, and the tick taken before a wake, because the display
    // link only fires while the run loop runs: a wake flood that skipped the pump starved the
    // frames (66 of 240), as a wake ahead of the tick did on Windows (44 of 330).
    ionMacFrameSync();
    waitForEvent();
    SDL_Event ev;
    while (SDL_PollEvent(&ev)) handleSdlEvent(&ev);
    atomic_store(&s_nudgePending, 0);

    if (ion_input_next()) return 4;
    if (ion_wevt_pop(&s_last_wevt_id, &s_last_wevt_type)) return 3;
    if (ion_queue_pop()) return 2;
    if (emitDueFrames()) return 4;
    if (atomic_exchange(&s_wakePending, 0)) return 6;
    if (atomic_exchange(&s_mscReady, 0) || mscDue()) return 5;
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

