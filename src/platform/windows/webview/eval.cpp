// Ion Windows — ionEvalJS: MS calls this to inject JS into the webview's
// main world. Mirrors mac's webview/eval.m.
//
// Phase 1 stubbed this as a no-op (poll.c). Phase 2 wires it to WebView2's
// `ExecuteScript`. Called from common code via the bridge.h `ionEvalJS`
// signature — exposed here as `extern "C"`.

#include "internal.hpp"
#include "../utf8.h"

#include <cstdio>
#include <cstdlib>

extern "C" void ionEvalJS(const char *js) {
    if (js == nullptr || js[0] == '\0') return;

    WebView2State *st = ionGetWebView2State();
    if (st == nullptr || !st->webview) {
        // Webview not ready yet — silently drop. In practice this only happens
        // if MS code calls `invoke()` before the WebView2 async init chain has
        // completed. The mac side has the same property (WKWebView is async).
        fprintf(stderr, "[ion] ionEvalJS: webview not ready, dropping JS\n");
        return;
    }

    wchar_t *wjs = ionUtf8ToWide(js);
    if (wjs == nullptr) return;

    // No-op callback — we don't care about the script's return value here
    // (invoke() is fire-and-forget for the MS→JS direction).
    st->webview->ExecuteScript(wjs, nullptr);
    free(wjs);
}
