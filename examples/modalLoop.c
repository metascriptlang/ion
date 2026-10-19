#include "modalLoop.h"

#include <windows.h>
#include <stdio.h>

void ionWakeLoop(void);

#define SCENARIO_MS 2000
#define ENTER_WAIT_MS 1000

enum { KindFrame, KindTimer, KindWake, KindCount };

static volatile LONG s_count[KindCount];
static volatile LONG s_wakesSent;
static volatile LONG s_done;
static LARGE_INTEGER s_freq;
static HWND s_hwnd;
static WNDPROC s_orig;
static HANDLE s_entered;
static HANDLE s_exited;
static LONG s_enterSnap[KindCount + 1];
static LONG s_exitSnap[KindCount + 1];
static double s_enterMs;
static double s_exitMs;
static int s_scenario;

static double nowMs(void) {
    LARGE_INTEGER t;
    QueryPerformanceCounter(&t);
    return (double)t.QuadPart * 1000.0 / (double)s_freq.QuadPart;
}

static void snapshot(LONG *into) {
    for (int k = 0; k < KindCount; k++) into[k] = s_count[k];
    into[KindCount] = s_wakesSent;
}

static LRESULT CALLBACK probeProc(HWND h, UINT m, WPARAM w, LPARAM l) {
    if (m == WM_ENTERSIZEMOVE) {
        snapshot(s_enterSnap);
        s_enterMs = nowMs();
        SetEvent(s_entered);
    }
    LRESULT r = CallWindowProcW(s_orig, h, m, w, l);
    if (m == WM_EXITSIZEMOVE) {
        snapshot(s_exitSnap);
        s_exitMs = nowMs();
        SetEvent(s_exited);
    }
    return r;
}

static DWORD WINAPI wakeThread(void *arg) {
    (void)arg;
    HANDLE timer = CreateWaitableTimerExW(NULL, NULL, CREATE_WAITABLE_TIMER_HIGH_RESOLUTION, TIMER_ALL_ACCESS);
    LARGE_INTEGER due;
    due.QuadPart = -50000;
    SetWaitableTimer(timer, &due, 5, NULL, NULL, FALSE);
    for (;;) {
        WaitForSingleObject(timer, INFINITE);
        InterlockedIncrement(&s_wakesSent);
        ionWakeLoop();
    }
    return 0;
}

int modalInit(void) {
    QueryPerformanceFrequency(&s_freq);
    s_hwnd = FindWindowW(NULL, L"Ion modal loop probe");
    if (s_hwnd == NULL) return 0;
    s_entered = CreateEventW(NULL, TRUE, FALSE, NULL);
    s_exited = CreateEventW(NULL, TRUE, FALSE, NULL);
    s_orig = (WNDPROC)SetWindowLongPtrW(s_hwnd, GWLP_WNDPROC, (LONG_PTR)probeProc);
    HANDLE t = CreateThread(NULL, 0, wakeThread, NULL, 0, NULL);
    if (t != NULL) CloseHandle(t);
    return 1;
}

void modalCount(int kind) { InterlockedIncrement(&s_count[kind]); }

static void postKey(WORD vk) {
    PostMessageW(s_hwnd, WM_KEYDOWN, vk, 0);
    PostMessageW(s_hwnd, WM_KEYUP, vk, 0);
}

static void line(const char *name, double ms, const LONG *a, const LONG *b) {
    printf("%s window=%.1fms frames=%ld timer10ms=%ld wakeHandlerRuns=%ld wakesSent=%ld\n", name, ms,
           b[KindFrame] - a[KindFrame], b[KindTimer] - a[KindTimer], b[KindWake] - a[KindWake], b[KindCount] - a[KindCount]);
    fflush(stdout);
}

static DWORD WINAPI scenarioThread(void *arg) {
    (void)arg;
    int sc = s_scenario;
    if (sc == 0) {
        LONG a[KindCount + 1], b[KindCount + 1];
        snapshot(a);
        double t0 = nowMs();
        Sleep(SCENARIO_MS);
        snapshot(b);
        line("control          ", nowMs() - t0, a, b);
    } else {
        const char *name = sc == 1 ? "modal SC_MOVE    " : "modal SC_SIZE    ";
        POINT cursor;
        GetCursorPos(&cursor);
        ResetEvent(s_entered);
        ResetEvent(s_exited);
        double post = nowMs();
        PostMessageW(s_hwnd, WM_SYSCOMMAND, sc == 1 ? SC_MOVE : SC_SIZE, 0);
        if (WaitForSingleObject(s_entered, ENTER_WAIT_MS) != WAIT_OBJECT_0) {
            printf("%s no WM_ENTERSIZEMOVE within %d ms of the post\n", name, ENTER_WAIT_MS);
        } else {
            printf("%s WM_ENTERSIZEMOVE %.1f ms after the post\n", name, s_enterMs - post);
            Sleep(SCENARIO_MS);
            double esc = nowMs();
            postKey(VK_ESCAPE);
            if (WaitForSingleObject(s_exited, ENTER_WAIT_MS) != WAIT_OBJECT_0) {
                printf("%s no WM_EXITSIZEMOVE after Escape; posting Return\n", name);
                postKey(VK_RETURN);
                WaitForSingleObject(s_exited, ENTER_WAIT_MS);
            }
            printf("%s WM_EXITSIZEMOVE %.1f ms after the Escape post\n", name, s_exitMs - esc);
            line(name, s_exitMs - s_enterMs, s_enterSnap, s_exitSnap);
        }
        SetCursorPos(cursor.x, cursor.y);
    }
    InterlockedExchange(&s_done, 1);
    return 0;
}

void modalRun(int scenario) {
    s_scenario = scenario;
    InterlockedExchange(&s_done, 0);
    HANDLE t = CreateThread(NULL, 0, scenarioThread, NULL, 0, NULL);
    if (t != NULL) CloseHandle(t);
}

int modalDone(void) { return (int)s_done; }
