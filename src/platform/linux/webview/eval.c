// Ion Linux — ionEvalJS via webkit_web_view_run_javascript.
//
// Mirrors mac webview/eval.m + win webview/eval.cpp. Fire-and-forget; we
// don't care about the result (the JS handler is responsible for routing
// any return value back via window.__ion__).

#include "../state.h"
#include "../../bridge.h"

#include <webkit2/webkit2.h>

void ionEvalJS(const char *js) {
    if (s_webView == NULL || js == NULL) return;
    // Pass NULL for cancellable, callback, user_data — discard result.
    webkit_web_view_run_javascript(s_webView, js, NULL, NULL, NULL);
}
