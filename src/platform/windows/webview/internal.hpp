// Ion Windows — WebView2 C++ shared types.
//
// Only included from .cpp files under webview/. C-side state.h carries an
// opaque `void *s_webview2State` that gets cast to `WebView2State *` here.
//
// MinGW gap: zig's bundled MinGW ships `wrl/client.h` (ComPtr) but NOT
// `wrl/event.h` (Callback<>). Each event-handler interface gets a
// hand-rolled class implementing IUnknown + the matching `Invoke()` — the
// pattern is uniform: AddRef/Release ref-count, QueryInterface checks
// IUnknown + the specific event interface, Invoke routes to ion logic.

#ifndef ION_WINDOWS_WEBVIEW_INTERNAL_HPP
#define ION_WINDOWS_WEBVIEW_INTERNAL_HPP

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <wrl/client.h>
#include <WebView2.h>

#include "../state.h"

struct WebView2State {
    Microsoft::WRL::ComPtr<ICoreWebView2Environment> env;
    Microsoft::WRL::ComPtr<ICoreWebView2Controller> controller;
    Microsoft::WRL::ComPtr<ICoreWebView2CompositionController> composition;
    Microsoft::WRL::ComPtr<ICoreWebView2>           webview;

    // Tokens for the events we subscribe to — kept so Shutdown can `remove_*`
    // them deterministically before releasing the webview ComPtr.
    EventRegistrationToken navStartingToken       { 0 };
    EventRegistrationToken messageToken           { 0 };
    EventRegistrationToken resourceRequestedToken { 0 };
    EventRegistrationToken cursorChangedToken     { 0 };
    HCURSOR cursor { nullptr };

    // URL to navigate to once the controller is ready. strdup'd in
    // ionWebView2Start; freed after Navigate() fires.
    char *pendingUrl { nullptr };
};

// Accessor for the C++ side of files. Returns nullptr if WebView2 isn't
// initialized yet (init not started, or post-shutdown).
inline WebView2State *ionGetWebView2State() {
    return static_cast<WebView2State *>(s_webview2State);
}

// Attach the WebMessageReceived handler. Defined in webview/messaging.cpp.
// Validates invoke_key per message; enqueues `(name, payload)` to the ion
// queue on success. Returns 0 on success, non-zero on attach failure.
HRESULT ionAttachMessageHandler(ICoreWebView2 *webview, EventRegistrationToken *outToken);

// Attach the NavigationStarting handler. Defined in webview/nav.cpp.
// Allows ion://, asset://, http(s)://, about:, data:; routes user-clicked
// http(s)/mailto to system browser; BLOCKS file:// (opaque-origin trap).
HRESULT ionAttachNavHandler(ICoreWebView2 *webview, EventRegistrationToken *outToken);

// Build an ICoreWebView2EnvironmentOptions instance whose
// CustomSchemeRegistrations array carries every scheme currently in the
// proto registry. Returns nullptr if none. Caller passes to createEnv +
// releases the ref. Defined in webview/protocol.cpp.
ICoreWebView2EnvironmentOptions *ionBuildEnvOptions();

// Attach the WebResourceRequested handler for every registered scheme.
// Must be called AFTER webview exists. Defined in webview/protocol.cpp.
HRESULT ionAttachResourceHandler(ICoreWebView2 *webview, EventRegistrationToken *outToken);

#endif
