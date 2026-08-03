// Cross-platform helpers for bridging raw C strings to MS native `msString`.
// macOS additionally has `nsStringToMs` (NSString → msString) in
// platform/macos/internal.h since Cocoa types aren't available here.
//
// MS_EMPTY_STRING is a zero/NULL-payload msString singleton — no alloc.
// Use it as the sentinel for "empty / not found / error" instead of
// `msStringFromCStr("")` (which would alloc a 0-byte payload).

#ifndef ION_COMMON_STRCONV_H
#define ION_COMMON_STRCONV_H

#include "runtime/core/string.h"

#ifdef __cplusplus
extern "C" {
#endif

// Wrap a NUL-terminated C string into an msString. NULL or empty → MS_EMPTY_STRING.
static inline msString cStringToMs(const char *s) {
    return (s && s[0]) ? msStringFromCStr(s) : MS_EMPTY_STRING;
}

#ifdef __cplusplus
}
#endif

#endif
