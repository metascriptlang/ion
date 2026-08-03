// Webview bootstrap JS template — shared by every platform's webview layer.
//
// The bootstrap is injected at document-start into every page the webview
// loads. It defines `window.__ion__` (the minimal native-transport surface
// consumed by @metascriptlang/ion) plus the auto console-relay that pipes
// webview console.{log,warn,error,info} + window.onerror + unhandledrejection
// back to MS stdout for debugging.
//
// Only ONE thing varies per platform: how JS hands an envelope object to
// the native side. mac WKWebView uses `window.webkit.messageHandlers.ion`;
// Windows WebView2 uses `window.chrome.webview`. Everything else — the
// invoke_key closure shape, the `__ion__` object frozen on window, the
// console relay, the error forwarders — is identical and lives here.

#ifndef ION_BOOTSTRAP_H
#define ION_BOOTSTRAP_H

#ifdef __cplusplus
extern "C" {
#endif

// Build the bootstrap JS for this platform.
//
// `invokeKey`: the per-launch hex token from `ion_invoke_key()` — embedded
//   in a closure so iframes / bookmarklets / scripts injected outside our
//   bootstrap cannot forge it.
// `nativePostBody`: ONE-LINE JS body of `function nativePost(envelope) { ... }`
//   — the platform's webview→native send call. Conventions:
//     macOS WKWebView:   "window.webkit.messageHandlers.ion.postMessage(envelope);"
//     Windows WebView2:  "window.chrome.webview.postMessage(envelope);"
//   Must not contain `%` characters (the template is rendered via snprintf).
//
// Returns a NUL-terminated malloc'd JS string. Caller must `free()` it.
// Returns NULL only on allocation failure.
//
// _w variant takes the window label, which is exposed to JS as
// `window.__ion__.label`. Old single-arg form is a wrapper that passes "".
char *ion_build_bootstrap_js_w(const char *invokeKey, const char *windowLabel,
                               const char *nativePostBody);
char *ion_build_bootstrap_js(const char *invokeKey, const char *nativePostBody);

#ifdef __cplusplus
}
#endif

#endif
