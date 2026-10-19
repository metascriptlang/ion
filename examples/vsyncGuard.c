// Measures DCompositionWaitForCompositorClock the way ion's vsyncThread calls it: a loop at
// THREAD_PRIORITY_TIME_CRITICAL, no handles, INFINITE timeout. Logs the return value and the
// interval between returns per phase while the probe's own window is visible, minimized,
// restored and covered by a second topmost window of the probe, then once more with a 200 ms
// sleep before each call (the first call after ion parks the thread). Touches no other window.
//
//   vsyncGuard.exe [guard]      writes the per-phase table to stdout
//   vsyncGuard.exe [guard] --long <seconds>
//                               one visible window and the clock thread for that long; one line
//                               per call that took under 1 ms or over 3 periods
//
// With `guard` the loop treats a call that took under 1 ms as early and sleeps one refresh
// period (gpui's vsync.rs mechanism), so the two interval distributions can be compared.
//
// Build: zig cc -O1 examples/vsyncGuard.c -o vsyncGuard.exe -luser32 -ldwmapi

#include <windows.h>
#include <dwmapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef DWORD (WINAPI *WaitFn)(UINT count, const HANDLE *handles, DWORD timeoutMs);

#define MAX_SAMPLES 200000
#define PHASE_MS 3000

static WaitFn s_wait;
static LARGE_INTEGER s_freq;
static int s_guard;
static double s_periodMs;
static volatile LONG s_phase;
static volatile LONG s_stop;
static int s_long;
static LONG s_longCalls;
static LONG s_longLogged;
static LONGLONG s_longStart;

#define LONG_LOG_CAP 200000

static double s_interval[5][MAX_SAMPLES];
static double s_call[5][MAX_SAMPLES];
static DWORD s_ret[5][MAX_SAMPLES];
static LONG s_count[5];

static double ms(LONGLONG ticks) { return (double)ticks * 1000.0 / (double)s_freq.QuadPart; }

static DWORD WINAPI clockThread(void *arg) {
    (void)arg;
    HANDLE timer = CreateWaitableTimerExW(NULL, NULL, CREATE_WAITABLE_TIMER_HIGH_RESOLUTION, TIMER_ALL_ACCESS);
    LARGE_INTEGER last = {0};
    while (!s_stop) {
        LARGE_INTEGER t0, t1;
        if (s_phase == 4) Sleep(200);
        QueryPerformanceCounter(&t0);
        DWORD r = s_wait(0, NULL, INFINITE);
        QueryPerformanceCounter(&t1);
        double call = ms(t1.QuadPart - t0.QuadPart);
        if (s_guard && call < 1.0) {
            LARGE_INTEGER due;
            due.QuadPart = -(LONGLONG)(s_periodMs * 10000.0);
            SetWaitableTimer(timer, &due, 0, NULL, NULL, FALSE);
            WaitForSingleObject(timer, INFINITE);
            QueryPerformanceCounter(&t1);
        }
        if (s_long) {
            s_longCalls++;
            if ((call < 1.0 || call > 3.0 * s_periodMs) && s_longLogged < LONG_LOG_CAP) {
                s_longLogged++;
                printf("t=%.3f s call=%.3f ms interval=%.3f ms ret=%lu\n", ms(t1.QuadPart - s_longStart) / 1000.0, call,
                       last.QuadPart ? ms(t1.QuadPart - last.QuadPart) : 0.0, r);
                fflush(stdout);
            }
            last = t1;
            continue;
        }
        int p = (int)s_phase;
        LONG n = s_count[p];
        if (last.QuadPart != 0 && n < MAX_SAMPLES) {
            s_interval[p][n] = ms(t1.QuadPart - last.QuadPart);
            s_call[p][n] = call;
            s_ret[p][n] = r;
            s_count[p] = n + 1;
        }
        last = t1;
    }
    return 0;
}

static int cmp(const void *a, const void *b) {
    double x = *(const double *)a, y = *(const double *)b;
    return x < y ? -1 : x > y;
}

static void report(const char *name, int p) {
    LONG n = s_count[p];
    if (n == 0) { printf("%-10s no samples\n", name); return; }
    double *iv = malloc(sizeof(double) * n);
    double *cl = malloc(sizeof(double) * n);
    memcpy(iv, s_interval[p], sizeof(double) * n);
    memcpy(cl, s_call[p], sizeof(double) * n);
    qsort(iv, n, sizeof(double), cmp);
    qsort(cl, n, sizeof(double), cmp);
    int below1 = 0;
    DWORD vals[8]; int counts[8]; int nv = 0;
    for (LONG i = 0; i < n; i++) {
        if (s_interval[p][i] < 1.0) below1++;
        int k = 0;
        while (k < nv && vals[k] != s_ret[p][i]) k++;
        if (k == nv && nv < 8) { vals[nv] = s_ret[p][i]; counts[nv++] = 0; }
        if (k < nv) counts[k]++;
    }
    printf("%-10s n=%ld interval ms min=%.2f p50=%.2f p99=%.2f max=%.2f below1ms=%d | call ms min=%.2f p50=%.2f max=%.2f | ret:",
           name, n, iv[0], iv[n / 2], iv[(n * 99) / 100], iv[n - 1], below1, cl[0], cl[n / 2], cl[n - 1]);
    for (int k = 0; k < nv; k++) printf(" %lu x%d", vals[k], counts[k]);
    printf("\n");
    if (p == 4) {
        printf("%-10s calls ms:", name);
        for (LONG i = 0; i < n; i++) printf(" %.1f", s_call[p][i]);
        printf("\n");
    }
    free(iv);
    free(cl);
}

static LRESULT CALLBACK proc(HWND h, UINT m, WPARAM w, LPARAM l) {
    return DefWindowProcW(h, m, w, l);
}

static void pump(DWORD totalMs) {
    DWORD end = GetTickCount() + totalMs;
    while ((LONG)(end - GetTickCount()) > 0) {
        MSG msg;
        while (PeekMessageW(&msg, NULL, 0, 0, PM_REMOVE)) { TranslateMessage(&msg); DispatchMessageW(&msg); }
        MsgWaitForMultipleObjects(0, NULL, FALSE, 10, QS_ALLINPUT);
    }
}

int main(int argc, char **argv) {
    double longSeconds = 0;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "guard") == 0) s_guard = 1;
        else if (strcmp(argv[i], "--long") == 0 && i + 1 < argc) { longSeconds = atof(argv[++i]); s_long = longSeconds > 0; }
        else if (strcmp(argv[i], "plain") != 0) { printf("usage: vsyncGuard [plain|guard] [--long <seconds>]\n"); return 2; }
    }
    HMODULE dcomp = LoadLibraryW(L"dcomp.dll");
    s_wait = dcomp ? (WaitFn)(void *)GetProcAddress(dcomp, "DCompositionWaitForCompositorClock") : NULL;
    if (!s_wait) { printf("DCompositionWaitForCompositorClock not found\n"); return 1; }
    QueryPerformanceFrequency(&s_freq);
    DWM_TIMING_INFO ti;
    memset(&ti, 0, sizeof ti);
    ti.cbSize = sizeof ti;
    s_periodMs = 0;
    if (SUCCEEDED(DwmGetCompositionTimingInfo(NULL, &ti)) && ti.rateRefresh.uiNumerator)
        s_periodMs = 1000.0 * ti.rateRefresh.uiDenominator / ti.rateRefresh.uiNumerator;
    if (s_periodMs < 1.0) s_periodMs = 1000.0 / 60.0;
    printf("mode=%s refresh period %.3f ms\n", s_guard ? "guard" : "plain", s_periodMs);

    HINSTANCE inst = GetModuleHandleW(NULL);
    WNDCLASSW wc;
    memset(&wc, 0, sizeof wc);
    wc.lpfnWndProc = proc;
    wc.hInstance = inst;
    wc.lpszClassName = L"vsyncGuard";
    RegisterClassW(&wc);
    HWND win = CreateWindowExW(0, L"vsyncGuard", L"vsyncGuard probe", WS_OVERLAPPEDWINDOW | WS_VISIBLE, 200, 200, 400, 300, NULL, NULL, inst, NULL);
    HWND cover = NULL;

    LARGE_INTEGER start;
    QueryPerformanceCounter(&start);
    s_longStart = start.QuadPart;
    HANDLE th = CreateThread(NULL, 0, clockThread, NULL, 0, NULL);
    SetThreadPriority(th, THREAD_PRIORITY_TIME_CRITICAL);

    if (s_long) {
        pump((DWORD)(longSeconds * 1000.0));
        s_stop = 1;
        WaitForSingleObject(th, 2000);
        printf("long: %.1f s, calls=%ld logged=%ld (cap %d)\n", longSeconds, s_longCalls, s_longLogged, LONG_LOG_CAP);
        DestroyWindow(win);
        return 0;
    }

    pump(PHASE_MS);
    s_phase = 1;
    ShowWindow(win, SW_MINIMIZE);
    pump(PHASE_MS);
    s_phase = 2;
    ShowWindow(win, SW_RESTORE);
    pump(PHASE_MS);
    s_phase = 3;
    cover = CreateWindowExW(WS_EX_TOPMOST | WS_EX_NOACTIVATE, L"vsyncGuard", L"vsyncGuard cover", WS_POPUP | WS_VISIBLE, 150, 150, 500, 400, NULL, NULL, inst, NULL);
    pump(PHASE_MS);
    s_phase = 4;
    pump(PHASE_MS);
    s_stop = 1;
    WaitForSingleObject(th, 2000);

    report("visible", 0);
    report("minimized", 1);
        report("restored", 2);
    report("covered", 3);
    report("afterIdle", 4);
    DestroyWindow(cover);
    DestroyWindow(win);
    return 0;
}
