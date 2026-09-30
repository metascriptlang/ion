// Ion Windows — event pump + IPC message accessor.
//
// ionPollEvent blocks until it has something to return: an IPC message, an
// input or frame record, or quit. While waiting it sleeps in
// MsgWaitForMultipleObjectsEx on the message queue and, only while a surface
// is due a frame, on the vsync thread's tick event.
//
// WebView2 async callbacks (env created, controller created, web message
// received, navigation starting) are delivered through the Win32 message
// pump — DispatchMessageW below drives them.
//
// `ionEvalJS` is owned by webview/eval.cpp (C++ side touches the COM
// objects). This file only handles Win32 plumbing + queue drain.

#include "../state.h"
#include "../internal.h"
#include "../../bridge.h"
#include "../../common/queue.h"
#include "../../common/inputEvents.h"
#include "../../common/frameClock.h"

#include <stdio.h>

static HANDLE        s_want;
static HANDLE        s_tick;
static volatile LONG64 s_tickCounter;
static LARGE_INTEGER s_freq;
static int           s_clockFailed;

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

int ionPollEvent(void) {
    for (;;) {
        if (ion_queue_pop()) return 2;
        if (ion_input_next()) return 4;

        MSG msg;
        while (PeekMessageW(&msg, NULL, 0, 0, PM_REMOVE)) {
            if (msg.message == WM_QUIT) return 1;
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
        ionWinKeyFlush();

        if (ion_queue_pop()) return 2;
        if (ion_input_next()) return 4;

        // Window closed (s_mainHwnd cleared by WM_DESTROY) but no WM_QUIT yet
        // somehow — treat as quit so runLoop can exit cleanly.
        if (s_mainHwnd == NULL) return 1;

        int wanted = ion_frame_wanted() && startClock();
        if (s_tick == NULL) {
            MsgWaitForMultipleObjectsEx(0, NULL, INFINITE, QS_ALLINPUT, MWMO_INPUTAVAILABLE);
            continue;
        }
        if (wanted) SetEvent(s_want);
        else ResetEvent(s_want);
        DWORD r = MsgWaitForMultipleObjectsEx(1, &s_tick, INFINITE, QS_ALLINPUT, MWMO_INPUTAVAILABLE);
        if (r == WAIT_OBJECT_0) ion_frame_emit(tickMs());
    }
}

msString ionMessageName(void)    { return cStringToMs(ion_queue_last_name()); }
msString ionMessagePayload(void) { return cStringToMs(ion_queue_last_payload()); }
