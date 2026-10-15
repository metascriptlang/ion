#include "../state.h"
#include "../../bridge.h"
#include "../../common/webviewRegistry.h"

static WebKitWebView *viewOf(IonWebviewId id) {
    IonWebviewSlot *slot = ion_webview_get(id);
    return slot ? ((IonLinuxWebviewState *)slot->platformState)->view : NULL;
}

void ionWebviewEval(IonWebviewId id, const char *js) {
    WebKitWebView *view = viewOf(id);
    if (view == NULL || js == NULL) return;
    webkit_web_view_evaluate_javascript(view, js, -1, NULL, NULL, NULL, NULL, NULL);
}

void ionWebviewNavigate(IonWebviewId id, const char *url) {
    WebKitWebView *view = viewOf(id);
    if (view == NULL || url == NULL || url[0] == '\0') return;
    webkit_web_view_load_uri(view, url);
}
