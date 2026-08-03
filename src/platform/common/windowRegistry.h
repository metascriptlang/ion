// Window registry — label → opaque platform state.
//
// Single-threaded slot table shared by every platform. The native bridge
// (window.m / window.c) allocates a platform-specific state struct
// (IonMacWindowState, IonWinWindowState, IonLinuxWindowState) and stores
// the pointer here. Lookups by id are O(1) (array index); by label O(N)
// linear scan over ION_MAX_WINDOWS slots.
//
// Lifetime: the platform layer owns `platformState`. Registry only holds
// the pointer. `ion_registry_free` clears the slot but does NOT free the
// struct — the caller (window.m) is responsible for tearing down native
// resources before calling free.

#ifndef ION_WINDOW_REGISTRY_H
#define ION_WINDOW_REGISTRY_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef int32_t IonWindowId;
#define ION_WINDOW_INVALID  ((IonWindowId)-1)
#define ION_MAX_WINDOWS     16
#define ION_LABEL_MAX       64    // inline label buffer; longer labels rejected

typedef struct {
    int          active;                 // 0 = free slot, 1 = in use
    char         label[ION_LABEL_MAX];   // NUL-terminated; "" when free
    void        *platformState;          // opaque → platform-specific struct
} IonWindowSlot;

// Allocate a slot for `label`. Returns ION_WINDOW_INVALID if:
//   - label is NULL / empty / longer than ION_LABEL_MAX-1
//   - a slot with the same label already exists (duplicate label)
//   - all ION_MAX_WINDOWS slots are taken
// The returned slot has active=1, label copied in, platformState=NULL.
// Caller sets platformState after creating the native window.
IonWindowId    ion_registry_alloc(const char *label);

// Mark the slot free. Does NOT free platformState — caller tears that down
// first. Safe to call with ION_WINDOW_INVALID (no-op).
void           ion_registry_free(IonWindowId id);

// Get the slot for `id`. Returns NULL if id is out of range or the slot
// is not active. The returned pointer is valid until the next alloc/free.
IonWindowSlot *ion_registry_get(IonWindowId id);

// Find a slot by label. Returns the id or ION_WINDOW_INVALID if no active
// slot has that label.
IonWindowId    ion_registry_find(const char *label);

// Number of active slots.
int            ion_registry_count(void);

// Iterate: returns the next active id strictly greater than `prev`, or
// ION_WINDOW_INVALID when done. Pass ION_WINDOW_INVALID to start.
//
//   for (IonWindowId i = ion_registry_next(ION_WINDOW_INVALID);
//        i != ION_WINDOW_INVALID;
//        i = ion_registry_next(i)) {
//        ...
//   }
IonWindowId    ion_registry_next(IonWindowId prev);

#ifdef __cplusplus
}
#endif

#endif
