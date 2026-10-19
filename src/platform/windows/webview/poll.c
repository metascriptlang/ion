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

#include <dxgi.h>
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

// The vsync thread waits on the vblank of the display that paces the frame tick
// (IDXGIOutput::WaitForVBlank). DCompositionWaitForCompositorClock stalls 50-270 ms on its
// first call after about 250 ms idle (measured 2026-10-19); WaitForVBlank returns in 0-6 ms.
// The clock stays as the fallback when no output resolves. With several windows on different
// monitors the monitor of the window that requested a frame last paces every window.
#define VBLANK_RETRY_MS     1000
#define DEFAULT_PERIOD_MS   16.0

static volatile LONG_PTR s_pacingMonitor;
static IDXGIOutput *s_output;
static HMONITOR     s_outputMonitor;
static double       s_periodMs = DEFAULT_PERIOD_MS;
static ULONGLONG    s_resolveRetryAt;

static const GUID kIidFactory1 = {0x770aae78, 0xf26f, 0x4dba, {0xa8, 0x29, 0x25, 0x3c, 0x83, 0xd1, 0xb3, 0x87}};

static IDXGIOutput *outputOf(HMONITOR monitor) {
    typedef HRESULT (WINAPI *CreateFactoryFn)(REFIID, void **);
    HMODULE dxgi = LoadLibraryW(L"dxgi.dll");
    CreateFactoryFn create = dxgi ? (CreateFactoryFn)(void *)GetProcAddress(dxgi, "CreateDXGIFactory1") : NULL;
    IDXGIFactory1 *factory = NULL;
    if (create == NULL || FAILED(create(&kIidFactory1, (void **)&factory))) return NULL;
    IDXGIOutput *found = NULL;
    IDXGIAdapter1 *adapter;
    for (UINT i = 0; found == NULL && factory->lpVtbl->EnumAdapters1(factory, i, &adapter) == S_OK; i++) {
        IDXGIOutput *output;
        for (UINT j = 0; found == NULL && adapter->lpVtbl->EnumOutputs(adapter, j, &output) == S_OK; j++) {
            DXGI_OUTPUT_DESC desc;
            if (SUCCEEDED(output->lpVtbl->GetDesc(output, &desc)) && desc.Monitor == monitor) {
                DEVMODEW mode = {0};
                mode.dmSize = sizeof mode;
                s_periodMs = EnumDisplaySettingsW(desc.DeviceName, ENUM_CURRENT_SETTINGS, &mode) && mode.dmDisplayFrequency > 1
                                 ? 1000.0 / (double)mode.dmDisplayFrequency
                                 : DEFAULT_PERIOD_MS;
                found = output;
            } else {
                output->lpVtbl->Release(output);
            }
        }
        adapter->lpVtbl->Release(adapter);
    }
    factory->lpVtbl->Release(factory);
    return found;
}

static void dropOutput(void) {
    if (s_output != NULL) s_output->lpVtbl->Release(s_output);
    s_output = NULL;
    s_outputMonitor = NULL;
}

// Re-resolves when the pacing monitor changed, and retries a lost output once a second.
static void followPacingMonitor(void) {
    HMONITOR want = (HMONITOR)InterlockedCompareExchangePointer((PVOID volatile *)&s_pacingMonitor, NULL, NULL);
    if (want == NULL) want = MonitorFromPoint((POINT){0, 0}, MONITOR_DEFAULTTOPRIMARY);
    if (s_output != NULL && want == s_outputMonitor) return;
    ULONGLONG now = GetTickCount64();
    if (s_output == NULL && want == s_outputMonitor && now < s_resolveRetryAt) return;
    dropOutput();
    s_output = outputOf(want);
    s_outputMonitor = want;
    s_resolveRetryAt = now + VBLANK_RETRY_MS;
    if (s_output == NULL) fprintf(stderr, "[ion] frame clock: no DXGI output for the window's monitor, using the compositor clock\n");
}

static double qpcMs(LARGE_INTEGER a, LARGE_INTEGER b) {
    return (double)(b.QuadPart - a.QuadPart) * 1000.0 / (double)s_freq.QuadPart;
}

static DWORD WINAPI vsyncThread(void *arg) {
    (void)arg;
    for (;;) {
        WaitForSingleObject(s_want, INFINITE);
        followPacingMonitor();
        LARGE_INTEGER t0, t;
        QueryPerformanceCounter(&t0);
        int failed = 0;
        if (s_output != NULL) {
            if (FAILED(s_output->lpVtbl->WaitForVBlank(s_output))) {
                dropOutput();
                s_resolveRetryAt = 0;
                failed = 1;
            }
        } else {
            s_waitCompositorClock(0, NULL, INFINITE);
        }
        QueryPerformanceCounter(&t);
        InterlockedExchange64(&s_tickCounter, t.QuadPart);
        SetEvent(s_tick);
        // gpui vsync.rs:40-57: a failed or sub-millisecond wait means the monitor sleeps or
        // went away; sleep one period so the thread never spins.
        if (failed || qpcMs(t0, t) < 1.0) Sleep((DWORD)(s_periodMs + 0.5));
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

static void notePacingMonitor(void) {
    HWND hwnd = ionWinHwnd(ion_frame_pacing_window());
    if (hwnd != NULL)
        InterlockedExchangePointer((PVOID volatile *)&s_pacingMonitor, MonitorFromWindow(hwnd, MONITOR_DEFAULTTOPRIMARY));
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
        if (wanted) notePacingMonitor();
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
