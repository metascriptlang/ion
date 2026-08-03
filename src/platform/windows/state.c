// Windows-only globals + shim around the common IPC queue.

#include "state.h"
#include "../common/queue.h"

HWND      s_mainHwnd       = NULL;
HINSTANCE s_hInstance      = NULL;
void     *s_webview2State  = NULL;
char      s_coldStartUrl[2048] = {0};

void ionEnqueueMessage(const char *name, const char *payload) {
    ion_queue_push(name, payload ? payload : "");
}
