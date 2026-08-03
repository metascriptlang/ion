// Ion macOS — MS → JS bridge: evaluate JS in a webview's main world.
//
// ionEvalJS targets the "main" window via the s_webview global (v0 path).
// ionEvalJSWindow targets a specific window by id (multi-window path).

#import "../state.h"
#import "../../bridge.h"

void ionEvalJS(const char *js) {
    if (s_webview == nil || js == NULL) return;
    NSString *src = [NSString stringWithUTF8String:js];
    [s_webview evaluateJavaScript:src completionHandler:nil];
}

void ionEvalJSWindow(IonWindowId id, const char *js) {
    if (js == NULL) return;
    IonMacWindowState *st = ionMacWindowState(id);
    if (!st || st->webview == nil) return;
    NSString *src = [NSString stringWithUTF8String:js];
    [st->webview evaluateJavaScript:src completionHandler:nil];
}
