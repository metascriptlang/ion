// Ion Windows — event pump + IPC message accessor.
//
// ionPollEvent blocks until it has something to return: an IPC message, an
// input or frame record, a reason to run msc's loop, or quit. While waiting it
// sleeps in MsgWaitForMultipleObjectsEx on the message queue, the msc-ready
// event, the wake event and, only while a window is due a frame, the vsync
// thread's tick event. The wait times out when msc's next timer is due.
//
// msc's loop waits on an I/O completion port, which MsgWait cannot see. A
// watcher thread blocks on that port instead; when an entry arrives it puts
// the entry back, signals s_mscReady and parks until the loop thread has run
// msc (ionLoopArm), so it does not spin on the entry it just re-posted. This
// is Electron's NodeBindingsWin shape.
//
// WebView2 async callbacks (env created, controller created, web message
// received, navigation starting) are delivered through the Win32 message
// pump — DispatchMessageW below drives them.

#include "../state.h"
#include "../internal.h"
#include "../../bridge.h"
#include "../../common/queue.h"
#include "../../common/inputEvents.h"
#include "../../common/windowEvents.h"
#include "../../common/frameClock.h"
#include "../../common/mscLoop.h"
#include "runtime/promise/dispatch.h"

#include <stdio.h>

static IonWindowId   s_lastWevtId   = ION_WINDOW_INVALID;
static int           s_lastWevtType = 0;
static int           s_quit;

static HANDLE        s_want;
static HANDLE        s_tick;
static volatile LONG64 s_tickCounter;
static LARGE_INTEGER s_freq;
static int           s_clockFailed;

static HANDLE        s_wake;
static INIT_ONCE     s_wakeOnce = INIT_ONCE_STATIC_INIT;
static HANDLE        s_mscReady;
static HANDLE        s_mscDrained;
static int           s_mscTimed;
static ULONGLONG     s_mscDeadline;

typedef DWORD (WINAPI *WaitCompositorClockFn)(UINT count, const HANDLE *handles, DWORD timeoutMs);
static WaitCompositorClockFn s_waitCompositorClock;

static DWORD WINAPI vsyncThread(void *arg) {
    (void)arg;
    for (;;) {
        WaitForSingleObject(s_want, INFINITE);
        s_waitCompositorClock(0, NULL, INFINITE);
        LARGE_INTEGER t;
        QueryPerformanceCounter(&t);
        InterlockedExchange64(&s_tickCounter, t.QuadPart);
        SetEvent(s_tick);
    }
    return 0;
}

static int startClock(void) {
    if (s_tick != NULL) return 1;
    if (s_clockFailed) return 0;
    // DwmFlush measured as a busy wait (105% of a core at 165 Hz, 2026-09-24).
    // mingw's dcomp.h does not declare DCompositionWaitForCompositorClock.
    HMODULE dcomp = GetModuleHandleW(L"dcomp.dll");
    s_waitCompositorClock = dcomp ? (WaitCompositorClockFn)(void *)GetProcAddress(dcomp, "DCompositionWaitForCompositorClock") : NULL;
    if (s_waitCompositorClock == NULL) {
        fprintf(stderr, "[ion] frame clock: DCompositionWaitForCompositorClock not found (needs Windows 11)\n");
        s_clockFailed = 1;
        return 0;
    }
    QueryPerformanceFrequency(&s_freq);
    s_want = CreateEventW(NULL, TRUE, FALSE, NULL);
    s_tick = CreateEventW(NULL, FALSE, FALSE, NULL);
    HANDLE thread = CreateThread(NULL, 0, vsyncThread, NULL, 0, NULL);
    if (s_want == NULL || s_tick == NULL || thread == NULL) {
        fprintf(stderr, "[ion] frame clock: thread start failed (%lu)\n", GetLastError());
        s_clockFailed = 1;
        return 0;
    }
    SetThreadPriority(thread, THREAD_PRIORITY_TIME_CRITICAL);
    CloseHandle(thread);
    return 1;
}

static double tickMs(void) {
    return (double)InterlockedCompareExchange64(&s_tickCounter, 0, 0) * 1000.0 / (double)s_freq.QuadPart;
}

static BOOL CALLBACK createWake(PINIT_ONCE once, PVOID param, PVOID *ctx) {
    (void)once; (void)param; (void)ctx;
    s_wake = CreateEventW(NULL, FALSE, FALSE, NULL);
    return s_wake != NULL;
}

static void wakeEvent(void) {
    if (!InitOnceExecuteOnce(&s_wakeOnce, createWake, NULL, NULL)) {
        fprintf(stderr, "[ion] wake event: create failed (%lu)\n", GetLastError());
        abort();
    }
}

// winit's EventLoopProxy posts a message to its window (event_loop.rs:912);
// an event in the wait list does the same without needing a window.
void ionWakeLoop(void) {
    wakeEvent();
    SetEvent(s_wake);
}

static DWORD WINAPI mscWatcher(void *arg) {
    HANDLE iocp = (HANDLE)arg;
    for (;;) {
        DWORD bytes;
        ULONG_PTR key;
        OVERLAPPED *ov;
        BOOL ok = GetQueuedCompletionStatus(iocp, &bytes, &key, &ov, INFINITE);
        if (!ok && ov == NULL) return 0;
        // Reset before re-posting: a drain that sees the entry then comes
        // after the reset, so the wait below cannot pass on a stale signal.
        ResetEvent(s_mscDrained);
        PostQueuedCompletionStatus(iocp, bytes, key, ov);
        SetEvent(s_mscReady);
        WaitForSingleObject(s_mscDrained, INFINITE);
    }
}

static void startWatcher(void) {
    if (s_mscReady != NULL) return;
    s_mscReady = CreateEventW(NULL, FALSE, FALSE, NULL);
    s_mscDrained = CreateEventW(NULL, FALSE, FALSE, NULL);
    HANDLE thread = CreateThread(NULL, 0, mscWatcher, msGetDispatcher()->iocp, 0, NULL);
    if (s_mscReady == NULL || s_mscDrained == NULL || thread == NULL) {
        fprintf(stderr, "[ion] msc watcher: start failed (%lu)\n", GetLastError());
        abort();
    }
    CloseHandle(thread);
}

void ionLoopArm(void) {
    startWatcher();
    int delay = ion_msc_next_delay_ms();
    s_mscTimed = delay >= 0;
    if (s_mscTimed) s_mscDeadline = GetTickCount64() + (ULONGLONG)delay;
    SetEvent(s_mscDrained);
}

int ionPollEvent(void) {
    if (s_lastWevtType == ION_EVT_DESTROYED) {
        ionWinReleaseDestroyed(s_lastWevtId);
        s_lastWevtType = 0;
    }
    for (;;) {
        if (ion_wevt_pop(&s_lastWevtId, &s_lastWevtType)) return 3;
        if (ion_queue_pop()) return 2;
        if (ion_input_next()) return 4;

        // Quit waits until the queued lifecycle events (close-requested,
        // destroyed) have been delivered.
        MSG msg;
        while (!s_quit && PeekMessageW(&msg, NULL, 0, 0, PM_REMOVE)) {
            if (msg.message == WM_QUIT) { s_quit = 1; break; }
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
        ionWinKeyFlush();

        if (ion_wevt_pop(&s_lastWevtId, &s_lastWevtType)) return 3;
        if (ion_queue_pop()) return 2;
        if (ion_input_next()) return 4;

        if (s_quit || ionWindowCount() == 0) return 1;

        int wanted = ion_frame_wanted() && startClock();
        wakeEvent();
        HANDLE handles[3];
        DWORD count = 0;
        // The tick goes first: the wait reports the lowest signaled index, and a
        // wake flood would otherwise hide a pending tick. The tick fires at display
        // rate, so it cannot starve the wake in turn.
        DWORD tickIndex = (DWORD)-1;
        if (s_tick != NULL) {
            if (wanted) SetEvent(s_want);
            else ResetEvent(s_want);
            tickIndex = count;
            handles[count++] = s_tick;
        }
        DWORD wakeIndex = count;
        handles[count++] = s_wake;
        DWORD readyIndex = count;
        handles[count++] = s_mscReady;
        DWORD timeout = INFINITE;
        if (s_mscTimed) {
            ULONGLONG now = GetTickCount64();
            if (s_mscDeadline <= now) return 5;
            timeout = (DWORD)(s_mscDeadline - now);
        }
        DWORD r = MsgWaitForMultipleObjectsEx(count, handles, timeout, QS_ALLINPUT, MWMO_INPUTAVAILABLE);
        if (r == WAIT_FAILED) {
            fprintf(stderr, "[ion] MsgWaitForMultipleObjectsEx failed (%lu)\n", GetLastError());
            abort();
        }
        if (tickIndex != (DWORD)-1 && r == WAIT_OBJECT_0 + tickIndex) { ion_frame_emit(tickMs()); continue; }
        if (r == WAIT_OBJECT_0 + wakeIndex) return 6;
        if (r == WAIT_TIMEOUT || r == WAIT_OBJECT_0 + readyIndex) return 5;
    }
}

IonWindowId ionWindowEventId(void)   { return s_lastWevtId; }
int         ionWindowEventType(void) { return s_lastWevtType; }

msString ionMessageName(void)    { return cStringToMs(ion_queue_last_name()); }
msString ionMessagePayload(void) { return cStringToMs(ion_queue_last_payload()); }
