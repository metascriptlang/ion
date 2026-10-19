#include "frameLatency.h"

#include <windows.h>
#include <dwmapi.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

#define MAX_TRIALS 256

static double s_samples[8][MAX_TRIALS];
static int s_count[8];

double latStamp(void) {
    LARGE_INTEGER f, t;
    QueryPerformanceFrequency(&f);
    QueryPerformanceCounter(&t);
    return (double)t.QuadPart * 1000.0 / (double)f.QuadPart;
}

void latRecordSince(int phase, double t0) {
    if (s_count[phase] < MAX_TRIALS) s_samples[phase][s_count[phase]++] = latStamp() - t0;
}

static int cmp(const void *a, const void *b) {
    double x = *(const double *)a, y = *(const double *)b;
    return x < y ? -1 : x > y;
}

static double refreshPeriodMs(void) {
    DWM_TIMING_INFO ti;
    memset(&ti, 0, sizeof ti);
    ti.cbSize = sizeof ti;
    if (FAILED(DwmGetCompositionTimingInfo(NULL, &ti)) || ti.rateRefresh.uiNumerator == 0) return 0;
    return 1000.0 * ti.rateRefresh.uiDenominator / ti.rateRefresh.uiNumerator;
}

void latReport(int phase) {
    static const char *const names[3] = {"idle 250 ms, on demand", "idle 1000 ms, on demand", "continuous frames, request mid-stream"};
    const char *name = names[phase];
    int n = s_count[phase];
    if (n == 0) { printf("%s: no samples (refresh period %.3f ms)\n", name, refreshPeriodMs()); fflush(stdout); return; }
    double *s = malloc(sizeof(double) * n);
    for (int i = 0; i < n; i++) s[i] = s_samples[phase][i];
    qsort(s, n, sizeof(double), cmp);
    printf("%s: n=%d latency ms min=%.2f p50=%.2f p90=%.2f max=%.2f | refresh period %.3f ms\n", name, n, s[0], s[n / 2], s[(n * 9) / 10], s[n - 1], refreshPeriodMs());
    fflush(stdout);
    free(s);
}
