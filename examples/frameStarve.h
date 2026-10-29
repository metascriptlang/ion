#ifndef ION_EXAMPLE_FRAME_STARVE_H
#define ION_EXAMPLE_FRAME_STARVE_H

#ifdef __cplusplus
extern "C" {
#endif

// Milliseconds on a monotonic clock.
int  starveNowMs(void);
// Busy-waits `us` microseconds: the work a handler does per wake or timer run.
void starveSpinUs(int us);
// Starts a native thread that calls ionWakeLoop in a tight loop for `ms` milliseconds.
void starveWakeFlood(int ms);
// Starts a native thread that calls ionWakeLoop every `periodMs` for `ms` milliseconds.
void starveWakeEvery(int periodMs, int ms);
// Milliseconds since the first ionWakeLoop of starveWakeEvery not yet taken, or -1; takes it.
int  starveTakeWakeAgeMs(void);

#ifdef __cplusplus
}
#endif

#endif
