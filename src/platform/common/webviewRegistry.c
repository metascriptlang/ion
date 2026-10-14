#include "webviewRegistry.h"
#include "../bridge.h"
#include "strconv.h"

#include <string.h>

static IonWebviewSlot s_slots[ION_MAX_WEBVIEWS];

int ion_webview_alloc(const char *label, IonWindowId window) {
    if (label == NULL) return ION_WEBVIEW_INVALID;
    size_t len = strlen(label);
    if (len == 0 || len >= ION_LABEL_MAX) return ION_WEBVIEW_INVALID;
    int freeIdx = ION_WEBVIEW_INVALID;
    for (int i = 0; i < ION_MAX_WEBVIEWS; i++) {
        if (s_slots[i].active) {
            if (strcmp(s_slots[i].label, label) == 0) return ION_WEBVIEW_INVALID;
        } else if (freeIdx < 0) {
            freeIdx = i;
        }
    }
    if (freeIdx < 0) return ION_WEBVIEW_INVALID;
    IonWebviewSlot *slot = &s_slots[freeIdx];
    memset(slot, 0, sizeof *slot);
    slot->active = 1;
    memcpy(slot->label, label, len);
    slot->window = window;
    return freeIdx;
}

void ion_webview_free(int id) {
    if (id < 0 || id >= ION_MAX_WEBVIEWS) return;
    memset(&s_slots[id], 0, sizeof s_slots[id]);
}

IonWebviewSlot *ion_webview_get(int id) {
    if (id < 0 || id >= ION_MAX_WEBVIEWS || !s_slots[id].active) return NULL;
    return &s_slots[id];
}

int ion_webview_find(const char *label) {
    if (label == NULL) return ION_WEBVIEW_INVALID;
    for (int i = 0; i < ION_MAX_WEBVIEWS; i++)
        if (s_slots[i].active && strcmp(s_slots[i].label, label) == 0) return i;
    return ION_WEBVIEW_INVALID;
}

int ion_webview_next(int prev) {
    for (int i = prev < 0 ? 0 : prev + 1; i < ION_MAX_WEBVIEWS; i++)
        if (s_slots[i].active) return i;
    return ION_WEBVIEW_INVALID;
}

IonWebviewId ionFindWebview(const char *label) {
    return ion_webview_find(label);
}

msString ionWebviewLabel(IonWebviewId id) {
    IonWebviewSlot *slot = ion_webview_get(id);
    return slot ? cStringToMs(slot->label) : MS_EMPTY_STRING;
}

IonWindowId ionWebviewWindow(IonWebviewId id) {
    IonWebviewSlot *slot = ion_webview_get(id);
    return slot ? slot->window : ION_WINDOW_INVALID;
}
