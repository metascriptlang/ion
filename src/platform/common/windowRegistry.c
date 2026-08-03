#include "windowRegistry.h"

#include <stddef.h>
#include <string.h>

static IonWindowSlot s_slots[ION_MAX_WINDOWS];

IonWindowId ion_registry_alloc(const char *label) {
    if (label == NULL) return ION_WINDOW_INVALID;
    size_t len = strlen(label);
    if (len == 0 || len >= ION_LABEL_MAX) return ION_WINDOW_INVALID;

    int free_idx = -1;
    for (int i = 0; i < ION_MAX_WINDOWS; i = i + 1) {
        if (s_slots[i].active) {
            if (strcmp(s_slots[i].label, label) == 0) return ION_WINDOW_INVALID;
        } else if (free_idx < 0) {
            free_idx = i;
        }
    }
    if (free_idx < 0) return ION_WINDOW_INVALID;

    IonWindowSlot *slot = &s_slots[free_idx];
    slot->active = 1;
    memcpy(slot->label, label, len);
    slot->label[len] = '\0';
    slot->platformState = NULL;
    return (IonWindowId)free_idx;
}

void ion_registry_free(IonWindowId id) {
    if (id < 0 || id >= ION_MAX_WINDOWS) return;
    IonWindowSlot *slot = &s_slots[id];
    if (!slot->active) return;
    slot->active = 0;
    slot->label[0] = '\0';
    slot->platformState = NULL;
}

IonWindowSlot *ion_registry_get(IonWindowId id) {
    if (id < 0 || id >= ION_MAX_WINDOWS) return NULL;
    IonWindowSlot *slot = &s_slots[id];
    return slot->active ? slot : NULL;
}

IonWindowId ion_registry_find(const char *label) {
    if (label == NULL) return ION_WINDOW_INVALID;
    for (int i = 0; i < ION_MAX_WINDOWS; i = i + 1) {
        if (s_slots[i].active && strcmp(s_slots[i].label, label) == 0) {
            return (IonWindowId)i;
        }
    }
    return ION_WINDOW_INVALID;
}

int ion_registry_count(void) {
    int n = 0;
    for (int i = 0; i < ION_MAX_WINDOWS; i = i + 1) {
        if (s_slots[i].active) n = n + 1;
    }
    return n;
}

IonWindowId ion_registry_next(IonWindowId prev) {
    int start = (prev < 0) ? 0 : ((int)prev + 1);
    for (int i = start; i < ION_MAX_WINDOWS; i = i + 1) {
        if (s_slots[i].active) return (IonWindowId)i;
    }
    return ION_WINDOW_INVALID;
}

// Cross-platform public bridge functions — thin wrappers over the
// internal lower_snake_case helpers so MS-side FFI can use camelCase.
IonWindowId ionFindWindow(const char *label) {
    return ion_registry_find(label);
}

// Note: msString is defined in runtime/core/string.h via bridge.h, so this
// translation unit only sees it through that include path. We use the
// platform-provided cStringToMs (declared in common/strconv.h) to bridge.
#include "strconv.h"
#include <stdlib.h>

msString ionWindowLabel(IonWindowId id) {
    IonWindowSlot *slot = ion_registry_get(id);
    return cStringToMs(slot ? slot->label : "");
}

