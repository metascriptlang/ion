#ifndef ION_EXAMPLE_FRAME_LATENCY_H
#define ION_EXAMPLE_FRAME_LATENCY_H

#ifdef __cplusplus
extern "C" {
#endif

// Milliseconds on the QPC monotonic clock.
double latStamp(void);
// Records now minus t0 under a phase (0..7).
void latRecordSince(int phase, double t0);
// Prints a phase: 0 idle 250 ms, 1 idle 1000 ms, 2 continuous; count, min, p50, p90, max next to the refresh period.
void latReport(int phase);

#ifdef __cplusplus
}
#endif

#endif
