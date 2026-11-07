#include "../state.h"
#include "../internal.h"
#include "../../bridge.h"
#include "../../common/queue.h"
#include "../../common/inputEvents.h"
#include "../../common/frameClock.h"
#include "../../common/windowEvents.h"
#include "../../common/windowRegistry.h"
#include "../../common/mscLoop.h"
#include "runtime/promise/dispatch.h"

#include <gtk/gtk.h>
#include <glib-unix.h>

static IonWindowId s_lastWevtId   = ION_WINDOW_INVALID;
static int         s_lastWevtType = 0;
static gint        s_wakePending;
static int         s_wakeTaken;

void ionWakeLoop(void) {
    g_atomic_int_set(&s_wakePending, 1);
    g_main_context_wakeup(NULL);
}

// A destroyed window's registry slot stays until the loop has read its DESTROYED event,
// so the label lookup for that event still resolves.
void ionLinuxReleaseReadDestroyed(void) {
    if (s_lastWevtType != ION_EVT_DESTROYED) return;
    IonWindowSlot *slot = ion_registry_get(s_lastWevtId);
    if (slot && !slot->platformState) ion_registry_free(s_lastWevtId);
    s_lastWevtType = 0;
}

static int drain(void) {
    if (ion_wevt_pop(&s_lastWevtId, &s_lastWevtType)) return 3;
    if (ion_queue_pop()) return 2;
    if (ion_input_next()) return 4;
    return 0;
}

static int takeWake(void) {
    if (s_wakeTaken) return 0;
    s_wakeTaken = g_atomic_int_compare_and_exchange(&s_wakePending, 1, 0);
    return s_wakeTaken;
}

// msc's work wakes the GLib wait as macOS's watcher wakes Cocoa's (poll.m): its selector fd
// (epoll) turning readable, and its next timer deadline. Both sources are one-shot and re-armed
// by ionLoopArm after msRunOnce has run, so a descriptor msc has not drained yet cannot make
// the non-blocking iterations below spin.
static guint s_mscFdSource;
static guint s_mscTimer;
static int   s_mscDue;   // a source fired since ionLoopArm: msc has work, so do not block

static gboolean onMscFd(gint fd, GIOCondition condition, gpointer data) {
    (void)fd; (void)condition; (void)data;
    s_mscFdSource = 0;
    s_mscDue = 1;
    return G_SOURCE_REMOVE;
}

static gboolean onMscDeadline(gpointer data) {
    (void)data;
    s_mscTimer = 0;
    s_mscDue = 1;
    return G_SOURCE_REMOVE;
}

int ionPollEvent(void) {
    ionLinuxReleaseReadDestroyed();

    int got = drain();
    if (got) return got;

    // Each pump serves one wake and the frames due, as on macOS (poll.m).
    if (takeWake()) return 6;
    s_wakeTaken = 0;
    ionLinuxFrameSync();
    while (g_main_context_iteration(NULL, FALSE)) {}

    got = drain();
    if (got) return got;
    if (ionLinuxAllWindowsClosed()) return 1;

    if (!s_mscDue && !g_atomic_int_get(&s_wakePending)) g_main_context_iteration(NULL, TRUE);
    got = drain();
    if (got) return got;
    if (takeWake()) return 6;
    return 0;
}

msString    ionMessageName(void)     { return cStringToMs(ion_queue_last_name()); }
msString    ionMessagePayload(void)  { return cStringToMs(ion_queue_last_payload()); }
IonWindowId ionWindowEventId(void)   { return s_lastWevtId; }
int         ionWindowEventType(void) { return s_lastWevtType; }

void ionLoopArm(void) {
    s_mscDue = 0;
    int fd = msGetDispatcherSelectorFd();
    if (fd >= 0 && s_mscFdSource == 0) s_mscFdSource = g_unix_fd_add(fd, G_IO_IN, onMscFd, NULL);
    if (s_mscTimer) g_source_remove(s_mscTimer);
    s_mscTimer = 0;
    int delay = ion_msc_next_delay_ms();
    if (delay >= 0) s_mscTimer = g_timeout_add((guint)delay, onMscDeadline, NULL);
}

int ionPollReady(void) { return 0; }
