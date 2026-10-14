#ifndef ION_EXAMPLE_LOOP_WAKE_H
#define ION_EXAMPLE_LOOP_WAKE_H

#ifdef __cplusplus
extern "C" {
#endif

// Starts a raw native thread that calls ionWakeLoop after `ms` milliseconds.
void wakeAfter(int ms);
// Milliseconds since the first call.
int  elapsedMs(void);

#ifdef __cplusplus
}
#endif

#endif
