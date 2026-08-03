// Platform-detected secure RNG. arc4random on Apple/BSD, getrandom on Linux,
// BCryptGenRandom on Windows. Pick at compile time, no runtime dispatch.

#include "randombytes.h"

#if defined(__APPLE__) || defined(__FreeBSD__) || defined(__OpenBSD__) || defined(__NetBSD__)
#include <stdlib.h>
int ion_random_bytes(void *out, size_t len) {
    arc4random_buf(out, len);
    return 0;  // arc4random is documented to never fail
}
#elif defined(__linux__)
#include <sys/random.h>
#include <errno.h>
int ion_random_bytes(void *out, size_t len) {
    unsigned char *p = (unsigned char *)out;
    size_t got = 0;
    while (got < len) {
        ssize_t n = getrandom(p + got, len - got, 0);
        if (n < 0) {
            if (errno == EINTR) continue;
            return -1;  // genuine failure — caller decides what to do
        }
        got += (size_t)n;
    }
    return 0;
}
#elif defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <bcrypt.h>
int ion_random_bytes(void *out, size_t len) {
    NTSTATUS status = BCryptGenRandom(NULL, (PUCHAR)out, (ULONG)len, BCRYPT_USE_SYSTEM_PREFERRED_RNG);
    return status == 0 ? 0 : -1;  // 0 == STATUS_SUCCESS
}
#else
#error "ion_random_bytes: unsupported platform"
#endif
