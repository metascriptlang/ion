#include "autoreleaseMacos.h"
#include "../src/platform/bridge.h"
#include <malloc/malloc.h>
#include <pthread.h>
#include <time.h>

static int32_t s_floodMs;

static int64_t nowMs(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (int64_t)t.tv_sec * 1000 + t.tv_nsec / 1000000;
}

static void *floodThread(void *arg) {
    (void)arg;
    int64_t end = nowMs() + s_floodMs;
    while (nowMs() < end) ionWakeLoop();
    return NULL;
}

void autoreleaseWakeFlood(int32_t ms) {
    s_floodMs = ms;
    pthread_t thread;
    if (pthread_create(&thread, NULL, floodThread, NULL) == 0) pthread_detach(thread);
}

int32_t autoreleaseBlocksInUse(void) {
    malloc_statistics_t stats;
    malloc_zone_statistics(NULL, &stats);
    return (int32_t)stats.blocks_in_use;
}
