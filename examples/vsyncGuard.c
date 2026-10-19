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
//   vsyncGuard.exe --idle       40 trials per mode of sleep 250 ms then three timed clock calls, for
//                               the plain wait, the wait with DCompositionBoostCompositorClock(TRUE)
//                               per trial, with it on for the whole run, and IDXGIOutput::WaitForVBlank;
//                               then the same with no sleep as the control
//
// With `guard` the loop treats a call that took under 1 ms as early and sleeps one refresh
// period (gpui's vsync.rs mechanism), so the two interval distributions can be compared.
//
// Build: zig cc -O1 examples/vsyncGuard.c -o vsyncGuard.exe -luser32 -ldwmapi -ldxgi -ldxguid

#include <windows.h>
#include <dwmapi.h>
#include <dxgi.h>
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

typedef HRESULT (WINAPI *BoostFn)(BOOL enable);

#define TRIALS 40
#define MODES 4
static const char *const kModeName[MODES] = {"plain", "boost", "boostAll", "vblank"};
static BoostFn s_boost;
static IDXGIOutput *s_output;
static HWND s_idleWin;
static double s_idleCall[2][MODES][3][TRIALS];
static LONG s_idleRet[2][MODES];
static LONG s_boostRet[2][MODES];
static LONG s_boostOffRet[2][MODES];
static int s_idleGapMs;

static LONG oneWait(int mode) {
    if (mode == 3) return (LONG)s_output->lpVtbl->WaitForVBlank(s_output);
    return (LONG)s_wait(0, NULL, INFINITE);
}

static DWORD WINAPI idleThread(void *arg) {
    int control = (int)(INT_PTR)arg;
    for (int mode = 0; mode < MODES; mode++) {
        if (mode == 2) s_boostRet[control][mode] = (LONG)s_boost(TRUE);
        for (int t = 0; t < TRIALS; t++) {
            if (s_idleGapMs > 0 && !control) Sleep(s_idleGapMs);
            if (mode == 1) s_boostRet[control][mode] = (LONG)s_boost(TRUE);
            for (int c = 0; c < 3; c++) {
                LARGE_INTEGER t0, t1;
                QueryPerformanceCounter(&t0);
                s_idleRet[control][mode] = oneWait(mode);
                QueryPerformanceCounter(&t1);
                s_idleCall[control][mode][c][t] = ms(t1.QuadPart - t0.QuadPart);
            }
            if (mode == 1) s_boostOffRet[control][mode] = (LONG)s_boost(FALSE);
        }
        if (mode == 2) s_boostOffRet[control][mode] = (LONG)s_boost(FALSE);
        Sleep(500);
    }
    return 0;
}

static IDXGIOutput *outputOfWindow(HWND w) {
    HMONITOR mon = MonitorFromWindow(w, MONITOR_DEFAULTTONEAREST);
    IDXGIFactory1 *f = NULL;
    if (FAILED(CreateDXGIFactory1(&IID_IDXGIFactory1, (void **)&f))) return NULL;
    IDXGIOutput *found = NULL;
    IDXGIAdapter1 *a;
    for (UINT i = 0; !found && f->lpVtbl->EnumAdapters1(f, i, &a) == S_OK; i++) {
        IDXGIOutput *o;
        for (UINT j = 0; !found && a->lpVtbl->EnumOutputs(a, j, &o) == S_OK; j++) {
            DXGI_OUTPUT_DESC d;
            if (SUCCEEDED(o->lpVtbl->GetDesc(o, &d)) && d.Monitor == mon) found = o;
            else o->lpVtbl->Release(o);
        }
        a->lpVtbl->Release(a);
    }
    f->lpVtbl->Release(f);
    return found;
}

static int cmpd(const void *a, const void *b) { return cmp(a, b); }

static void idleRow(const char *label, double *v) {
    double s[TRIALS];
    memcpy(s, v, sizeof s);
    qsort(s, TRIALS, sizeof(double), cmpd);
    printf("  %-22s min=%7.2f p50=%7.2f p90=%7.2f max=%8.2f\n", label, s[0], s[TRIALS / 2], s[(TRIALS * 9) / 10], s[TRIALS - 1]);
}

static void idleReport(void) {
    for (int control = 0; control < 2; control++) {
        printf("%s (period %.3f ms, %d trials per mode)\n", control ? "control: back-to-back, no idle" : "afterIdle: sleep 250 ms before each trial", s_periodMs, TRIALS);
        for (int mode = 0; mode < MODES; mode++) {
            printf(" %s  last wait ret=0x%lx  boost(TRUE) ret=0x%lx  boost(FALSE) ret=0x%lx\n", kModeName[mode], (unsigned long)s_idleRet[control][mode],
                   (unsigned long)s_boostRet[control][mode], (unsigned long)s_boostOffRet[control][mode]);
            idleRow("call 1 (first) ms", s_idleCall[control][mode][0]);
            idleRow("call 2 ms", s_idleCall[control][mode][1]);
            idleRow("call 3 ms", s_idleCall[control][mode][2]);
        }
    }
}

static int runIdle(HWND win) {
    HMODULE dcomp = GetModuleHandleW(L"dcomp.dll");
    s_boost = dcomp ? (BoostFn)(void *)GetProcAddress(dcomp, "DCompositionBoostCompositorClock") : NULL;
    if (!s_boost) { printf("DCompositionBoostCompositorClock not found\n"); return 1; }
    s_output = outputOfWindow(win);
    if (!s_output) { printf("no DXGI output for the window's monitor\n"); return 1; }
    s_idleGapMs = 250;
    pump(500);
    for (int control = 1; control >= 0; control--) {
        HANDLE th = CreateThread(NULL, 0, idleThread, (void *)(INT_PTR)control, 0, NULL);
        SetThreadPriority(th, THREAD_PRIORITY_TIME_CRITICAL);
        while (WaitForSingleObject(th, 20) == WAIT_TIMEOUT) pump(1);
        CloseHandle(th);
    }
    idleReport();
    return 0;
}

int main(int argc, char **argv) {
    double longSeconds = 0;
    int idleCmp = 0;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--idle") == 0) idleCmp = 1;
        else if (strcmp(argv[i], "guard") == 0) s_guard = 1;
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
    if (idleCmp) {
        QueryPerformanceFrequency(&s_freq);
        int rc = runIdle(win);
        DestroyWindow(win);
        return rc;
    }

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
