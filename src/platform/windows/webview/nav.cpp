// Ion Windows — NavigationStarting handler.
//
// Mirrors mac's webview/nav_delegate.m. WebView2 fires NavigationStarting
// for every navigation request (initial load, link click, JS navigate,
// redirect, etc.). We consult common/navpolicy.c to decide:
//   - ALLOW    → let WebView2 navigate in-page (initial load, SPA routing, dev)
//   - EXTERNAL → cancel + open the URL in the system browser
//
// The policy is purely about KEEPING the webview pointed at our own content.
// `is_user_click` mirrors mac's WKNavigationTypeLinkActivated detection —
// we use WebView2's IsUserInitiated which fires true for user-clicked links.

#include "internal.hpp"
#include "../utf8.h"
#include "../../common/navpolicy.h"

#include <shellapi.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>

// Parse "scheme://host/..." into separate lowercase strings.
// Returns 1 on success, 0 if the URL doesn't have a scheme.
// `schemeOut` / `hostOut` are caller-provided buffers; values lowercased.
static int parseSchemeHost(const char *url, char *schemeOut, int schemeCap,
                                              char *hostOut, int hostCap) {
    if (url == nullptr) return 0;
    const char *colon = strstr(url, ":");
    if (colon == nullptr) return 0;
    int schemeLen = (int)(colon - url);
    if (schemeLen <= 0 || schemeLen >= schemeCap) return 0;
    for (int i = 0; i < schemeLen; i++) {
        char c = url[i];
        if (c >= 'A' && c <= 'Z') c = (char)(c + ('a' - 'A'));
        schemeOut[i] = c;
    }
    schemeOut[schemeLen] = '\0';

    // Host: only present when URL has "://" form. file:/// / about: / data:
    // have empty host — fine, navpolicy handles them.
    hostOut[0] = '\0';
    const char *hostStart = nullptr;
    if (colon[1] == '/' && colon[2] == '/') {
        hostStart = colon + 3;
        const char *hostEnd = hostStart;
        while (*hostEnd && *hostEnd != '/' && *hostEnd != '?' && *hostEnd != '#') hostEnd++;
        int hostLen = (int)(hostEnd - hostStart);
        if (hostLen >= hostCap) hostLen = hostCap - 1;
        for (int i = 0; i < hostLen; i++) {
            char c = hostStart[i];
            if (c >= 'A' && c <= 'Z') c = (char)(c + ('a' - 'A'));
            hostOut[i] = c;
        }
        hostOut[hostLen] = '\0';
    }
    return 1;
}

class NavStartingCallback final
    : public ICoreWebView2NavigationStartingEventHandler {
public:
    NavStartingCallback() : m_refs(1) {}

    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **ppv) override {
        if (!ppv) return E_POINTER;
        if (IsEqualIID(riid, IID_IUnknown) ||
            IsEqualIID(riid, IID_ICoreWebView2NavigationStartingEventHandler)) {
            *ppv = this; AddRef(); return S_OK;
        }
        *ppv = nullptr; return E_NOINTERFACE;
    }
    ULONG STDMETHODCALLTYPE AddRef()  override { return (ULONG)InterlockedIncrement(&m_refs); }
    ULONG STDMETHODCALLTYPE Release() override {
        LONG r = InterlockedDecrement(&m_refs);
        if (r == 0) delete this;
        return (ULONG)r;
    }

    HRESULT STDMETHODCALLTYPE Invoke(ICoreWebView2 *sender,
                                     ICoreWebView2NavigationStartingEventArgs *args) override {
        (void)sender;
        if (args == nullptr) return S_OK;

        LPWSTR uriW = nullptr;
        if (FAILED(args->get_Uri(&uriW)) || uriW == nullptr) return S_OK;

        BOOL isUser = FALSE;
        args->get_IsUserInitiated(&isUser);

        // UTF-16 → UTF-8 for the navpolicy decision. Pessimistic size (×4).
        char urlU8[2048];
        if (!ionWideToUtf8(uriW, urlU8, (int)sizeof(urlU8))) {
            CoTaskMemFree(uriW);
            return S_OK;
        }

        char scheme[32] = {0};
        char host[256]  = {0};
        if (!parseSchemeHost(urlU8, scheme, (int)sizeof(scheme), host, (int)sizeof(host))) {
            CoTaskMemFree(uriW);
            return S_OK;
        }

        ion_nav_decision_t decision = ion_nav_decide(scheme, host, isUser ? 1 : 0);
        if (decision == ION_NAV_EXTERNAL) {
            args->put_Cancel(TRUE);
            // Hand off to the system browser. ShellExecuteW handles http(s)+mailto.
            ShellExecuteW(NULL, L"open", uriW, NULL, NULL, SW_SHOWNORMAL);
        } else if (decision == ION_NAV_BLOCK) {
            // file:// only — opaque-origin trap. Log clear reason; cancel nav.
            // Mirrors macOS nav_delegate.m message.
            args->put_Cancel(TRUE);
            fprintf(stderr,
                "[ion] navigation blocked: %s — file:// has opaque origin which "
                "breaks pushState/localStorage/SW. Use ion:// (bundled) or "
                "asset:// (scoped) instead. See vendor/ion/CUSTOM-PROTOCOL.md\n",
                urlU8);
        }

        CoTaskMemFree(uriW);
        return S_OK;
    }

private:
    LONG m_refs;
};

HRESULT ionAttachNavHandler(ICoreWebView2 *webview, EventRegistrationToken *outToken) {
    if (webview == nullptr) return E_INVALIDARG;
    auto *cb = new NavStartingCallback();
    HRESULT hr = webview->add_NavigationStarting(cb, outToken);
    cb->Release();
    return hr;
}
