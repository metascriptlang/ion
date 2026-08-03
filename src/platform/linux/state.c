// Linux-only globals + shim around the common IPC queue.

#include "state.h"
#include "../common/queue.h"

GtkWidget     *s_mainWindow = NULL;
WebKitWebView *s_webView    = NULL;
char           s_coldStartUrl[2048] = {0};

void ionEnqueueMessage(const char *name, const char *payload) {
    ion_queue_push(name, payload ? payload : "");
}
