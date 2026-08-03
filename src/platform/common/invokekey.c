#include "invokekey.h"
#include "randombytes.h"
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

static char s_key[65] = {0};  // 64 hex chars + NUL

const char *ion_invoke_key(void) {
    if (s_key[0] == 0) {
        unsigned char bytes[32];
        if (ion_random_bytes(bytes, sizeof(bytes)) != 0) {
            // RNG failure is catastrophic for IPC security: with no key,
            // either we accept-all (insecure) or reject-all (broken). Abort
            // with a clear message — fail loudly, don't degrade silently.
            fprintf(stderr, "[ion] FATAL: secure random source unavailable; cannot generate invoke_key\n");
            abort();
        }
        static const char hex[] = "0123456789abcdef";
        for (size_t i = 0; i < sizeof(bytes); i++) {
            s_key[i * 2]     = hex[bytes[i] >> 4];
            s_key[i * 2 + 1] = hex[bytes[i] & 0xf];
        }
        s_key[64] = 0;
    }
    return s_key;
}

int ion_invoke_key_verify(const char *candidate) {
    if (candidate == NULL || *candidate == 0) return 0;
    return strcmp(candidate, ion_invoke_key()) == 0 ? 1 : 0;
}
