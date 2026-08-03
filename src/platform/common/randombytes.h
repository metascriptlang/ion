// Cross-platform secure random bytes. Backs invoke_key generation.
//
// Returns 0 on success, -1 on failure. Failure means the OS RNG denied us —
// for security primitives the caller should treat this as fatal (don't fall
// back to a weak source). ion_invoke_key() aborts on RNG failure for that
// reason.

#ifndef ION_RANDOMBYTES_H
#define ION_RANDOMBYTES_H

#include <stddef.h>

int ion_random_bytes(void *out, size_t len);

#endif
