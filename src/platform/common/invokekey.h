// Per-process invoke_key — random 32-byte token rendered as 64-char hex.
// Generated lazily on first call. Used to authenticate JS→native IPC; the
// token lives in a closure inside the bootstrap JS, so iframes / bookmarklets
// / content injected outside our bootstrap can't forge it.

#ifndef ION_INVOKEKEY_H
#define ION_INVOKEKEY_H

#ifdef __cplusplus
extern "C" {
#endif

// Returns the invoke_key as a NUL-terminated hex string.
// The pointer is valid for the lifetime of the process.
const char *ion_invoke_key(void);

// Returns 1 if `candidate` matches the invoke_key, 0 otherwise.
// NULL or empty candidate → 0.
int ion_invoke_key_verify(const char *candidate);

#ifdef __cplusplus
}
#endif

#endif
