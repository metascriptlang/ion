#include "loopWake.h"

#ifdef _WIN32
#include <windows.h>
#else
#include <pthread.h>
#include <time.h>
#include <unistd.h>
#endif

void ionWakeLoop(void);

static int nowMs(void) {
#ifdef _WIN32
    return (int)GetTickCount64();
#else
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (int)(t.tv_sec * 1000 + t.tv_nsec / 1000000);
#endif
}

int elapsedMs(void) {
    static int start = -1;
    if (start < 0) start = nowMs();
    return nowMs() - start;
}

static int s_delay;

#ifdef _WIN32
static DWORD WINAPI wakeThread(void *arg) {
    (void)arg;
    Sleep((DWORD)s_delay);
    ionWakeLoop();
    return 0;
}

void wakeAfter(int ms) {
    s_delay = ms;
    HANDLE thread = CreateThread(NULL, 0, wakeThread, NULL, 0, NULL);
    if (thread != NULL) CloseHandle(thread);
}
#else
static void *wakeThread(void *arg) {
    (void)arg;
    usleep((useconds_t)s_delay * 1000);
    ionWakeLoop();
    return NULL;
}

void wakeAfter(int ms) {
    s_delay = ms;
    pthread_t thread;
    if (pthread_create(&thread, NULL, wakeThread, NULL) == 0) pthread_detach(thread);
}
#endif
