#ifndef ION_WEBVIEW_REGISTRY_H
#define ION_WEBVIEW_REGISTRY_H

#include "windowRegistry.h"

#ifdef __cplusplus
extern "C" {
#endif

#define ION_MAX_WEBVIEWS 32

typedef struct {
    int          active;
    char         label[ION_LABEL_MAX];
    IonWindowId  window;
    void        *platformState;
} IonWebviewSlot;

int             ion_webview_alloc(const char *label, IonWindowId window);
void            ion_webview_free(int id);
IonWebviewSlot *ion_webview_get(int id);
int             ion_webview_find(const char *label);
int             ion_webview_next(int prev);

#ifdef __cplusplus
}
#endif

#endif
