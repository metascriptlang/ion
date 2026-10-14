#ifndef ION_MSC_LOOP_H
#define ION_MSC_LOOP_H

#ifdef __cplusplus
extern "C" {
#endif

// Milliseconds until msc's event loop next needs to run (0 = now), or -1
// when it has no timer and nothing queued. Runs any timer already due.
int ion_msc_next_delay_ms(void);

#ifdef __cplusplus
}
#endif

#endif
