#include "internal.hpp"
#include "../utf8.h"
extern "C" {
#include "../../bridge.h"
}

#include <cstdio>
#include <cstdlib>

extern "C" void ionWebviewEval(IonWebviewId id, const char *js) {
    if (js == nullptr || js[0] == '\0') return;
    WebView2State *st = ionWebView2At(id);
    if (st == nullptr || !st->webview) {
        fprintf(stderr, "[ion] ionWebviewEval: webview %d is not ready, dropping JS\n", id);
        return;
    }
    wchar_t *wjs = ionUtf8ToWide(js);
    if (wjs == nullptr) return;
    st->webview->ExecuteScript(wjs, nullptr);
    free(wjs);
}
