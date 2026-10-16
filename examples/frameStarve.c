#include "frameStarve.h"

#ifdef _WIN32
#include <windows.h>
#else
#include <pthread.h>
#include <time.h>
#include <unistd.h>
#endif

void ionWakeLoop(void);

int starveNowMs(void) {
#ifdef _WIN32
    return (int)GetTickCount64();
#else
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (int)(t.tv_sec * 1000 + t.tv_nsec / 1000000);
#endif
}

void starveSpinUs(int us) {
#ifdef _WIN32
    LARGE_INTEGER f, t0, t;
    QueryPerformanceFrequency(&f);
    QueryPerformanceCounter(&t0);
    do QueryPerformanceCounter(&t); while ((t.QuadPart - t0.QuadPart) * 1000000 / f.QuadPart < us);
#else
    struct timespec a, b;
    clock_gettime(CLOCK_MONOTONIC, &a);
    do clock_gettime(CLOCK_MONOTONIC, &b);
    while ((b.tv_sec - a.tv_sec) * 1000000L + (b.tv_nsec - a.tv_nsec) / 1000 < us);
#endif
}

static int s_floodMs;

#ifdef _WIN32
static DWORD WINAPI floodThread(void *arg) {
    (void)arg;
    int end = starveNowMs() + s_floodMs;
    while (starveNowMs() < end) ionWakeLoop();
    return 0;
}

void starveWakeFlood(int ms) {
    s_floodMs = ms;
    HANDLE thread = CreateThread(NULL, 0, floodThread, NULL, 0, NULL);
    if (thread != NULL) CloseHandle(thread);
}
#else
static void *floodThread(void *arg) {
    (void)arg;
    int end = starveNowMs() + s_floodMs;
    while (starveNowMs() < end) ionWakeLoop();
    return NULL;
}

void starveWakeFlood(int ms) {
    s_floodMs = ms;
    pthread_t thread;
    if (pthread_create(&thread, NULL, floodThread, NULL) == 0) pthread_detach(thread);
}
#endif
