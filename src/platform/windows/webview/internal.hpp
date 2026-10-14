// Ion Windows — WebView2 C++ shared types.
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
#include <dcomp.h>

#include "../state.h"
#include "../../common/windowRegistry.h"

struct WebView2State {
    int                  id         { -1 };
    IonWindowId          window     { ION_WINDOW_INVALID };
    HWND                 hwnd       { nullptr };
    IDCompositionVisual *visual     { nullptr };
    bool                 requested  { false };
    bool                 released   { false };

    Microsoft::WRL::ComPtr<ICoreWebView2Controller>            controller;
    Microsoft::WRL::ComPtr<ICoreWebView2CompositionController> composition;
    Microsoft::WRL::ComPtr<ICoreWebView2>                      webview;

    EventRegistrationToken navStartingToken       { 0 };
    EventRegistrationToken messageToken           { 0 };
    EventRegistrationToken resourceRequestedToken { 0 };
    EventRegistrationToken cursorChangedToken     { 0 };
    HCURSOR cursor { nullptr };

    char *pendingUrl  { nullptr };
    RECT  bounds      { 0, 0, 0, 0 };
    bool  visible     { true };
    bool  transparent { false };
};

WebView2State *ionWebView2At(int id);
ICoreWebView2Environment *ionWebView2Env();

// Attach the WebMessageReceived handler. Defined in webview/messaging.cpp.
// Validates invoke_key per message; enqueues `(name, payload)` tagged with
// the webview id on success.
HRESULT ionAttachMessageHandler(ICoreWebView2 *webview, int id, EventRegistrationToken *outToken);

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
