// Ion Windows — WebView2 custom URI scheme handler.
//
// Mirrors macOS WKURLSchemeHandler. Two halves:
//
//   1. ionBuildEnvOptions — called BEFORE CreateCoreWebView2EnvironmentWithOptions
//      in ionWebView2Start. Builds an ICoreWebView2EnvironmentOptions that
//      includes a CustomSchemeRegistrations array sourced from the proto
//      registry. WebView2 requires schemes declared at env creation; can't
//      add later.
//
//   2. ionAttachResourceHandler — called AFTER the controller is ready in
//      ControllerCreatedCallback. Adds a WebResourceRequestedFilter for each
//      registered scheme + a single WebResourceRequested event handler that
//      routes through ionProtoLookup → CreateWebResourceResponse.
//
// MinGW gap (per internal.hpp): zig's bundled MinGW ships wrl/client.h
// (ComPtr) but NOT wrl/implements.h with RuntimeClass templates the SDK
// header uses. We hand-roll all IUnknown impls, matching controller.cpp's
// AddRef/Release/QueryInterface pattern.

#include "internal.hpp"
#include "../utf8.h"
#include "../../common/protoReg.h"

#include <shlwapi.h>  // SHCreateMemStream
#include <cstdio>
#include <cstdlib>
#include <cstring>

using Microsoft::WRL::ComPtr;

// ---- IonCustomSchemeReg ---------------------------------------------------
// One per registered scheme. Implements ICoreWebView2CustomSchemeRegistration
// — a thin COM bag of properties (scheme name, treat-as-secure, allowed
// origins, authority component).

class IonCustomSchemeReg final : public ICoreWebView2CustomSchemeRegistration {
public:
    explicit IonCustomSchemeReg(const wchar_t *scheme) : m_refs(1) {
        size_t len = wcslen(scheme);
        m_scheme = (wchar_t *)CoTaskMemAlloc((len + 1) * sizeof(wchar_t));
        if (m_scheme != nullptr) {
            wcscpy_s(m_scheme, len + 1, scheme);
        }
    }
    ~IonCustomSchemeReg() {
        if (m_scheme) CoTaskMemFree(m_scheme);
    }

    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **ppv) override {
        if (!ppv) return E_POINTER;
        if (IsEqualIID(riid, IID_IUnknown) ||
            IsEqualIID(riid, IID_ICoreWebView2CustomSchemeRegistration)) {
            *ppv = static_cast<ICoreWebView2CustomSchemeRegistration *>(this);
            AddRef();
            return S_OK;
        }
        *ppv = nullptr;
        return E_NOINTERFACE;
    }
    ULONG STDMETHODCALLTYPE AddRef()  override { return (ULONG)InterlockedIncrement(&m_refs); }
    ULONG STDMETHODCALLTYPE Release() override {
        LONG r = InterlockedDecrement(&m_refs);
        if (r == 0) delete this;
        return (ULONG)r;
    }

    HRESULT STDMETHODCALLTYPE get_SchemeName(LPWSTR *value) override {
        if (!value) return E_POINTER;
        if (m_scheme == nullptr) { *value = nullptr; return S_OK; }
        size_t len = wcslen(m_scheme);
        *value = (LPWSTR)CoTaskMemAlloc((len + 1) * sizeof(wchar_t));
        if (!*value) return E_OUTOFMEMORY;
        wcscpy_s(*value, len + 1, m_scheme);
        return S_OK;
    }

    // Treat-as-secure: required so the scheme has powerful-feature access
    // (Service Workers, COOP/COEP, SharedArrayBuffer, secure-context fetch).
    // Equivalent to chrome://flags `unsafely-treat-insecure-origin-as-secure`
    // scoped to our scheme. We're shipping content from disk; we trust ourselves.
    HRESULT STDMETHODCALLTYPE get_TreatAsSecure(BOOL *value) override {
        if (!value) return E_POINTER;
        *value = TRUE;
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE put_TreatAsSecure(BOOL value) override { (void)value; return S_OK; }

    HRESULT STDMETHODCALLTYPE GetAllowedOrigins(UINT32 *count, LPWSTR **origins) override {
        if (count) *count = 0;
        if (origins) *origins = nullptr;
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE SetAllowedOrigins(UINT32 count, LPCWSTR *origins) override {
        (void)count; (void)origins;
        return S_OK;
    }

    // Has-authority: yes. <scheme>://localhost has a host component.
    HRESULT STDMETHODCALLTYPE get_HasAuthorityComponent(BOOL *value) override {
        if (!value) return E_POINTER;
        *value = TRUE;
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE put_HasAuthorityComponent(BOOL value) override { (void)value; return S_OK; }

private:
    LONG m_refs;
    wchar_t *m_scheme;
};

// Helper: CoTaskMemAlloc an empty wide string. WebView2 expects unset string
// options as alloc'd "" not nullptr (returning nullptr fails E_INVALIDARG
// during env validation).
static LPWSTR allocEmptyW() {
    LPWSTR s = (LPWSTR)CoTaskMemAlloc(sizeof(wchar_t));
    if (s) s[0] = 0;
    return s;
}

// Helper: CoTaskMemAlloc a copy of a wide string literal.
static LPWSTR allocWideCopy(const wchar_t *src) {
    size_t len = wcslen(src);
    LPWSTR s = (LPWSTR)CoTaskMemAlloc((len + 1) * sizeof(wchar_t));
    if (s) memcpy(s, src, (len + 1) * sizeof(wchar_t));
    return s;
}

// ---- IonEnvOptions --------------------------------------------------------
// Passed to CreateCoreWebView2EnvironmentWithOptions. Implements all four
// IEnvironmentOptions interfaces (v1 + v2 + v3 + v4). WebView2 QIs for every
// version it knows during validation; missing a version triggers E_INVALIDARG
// at CreateCoreWebView2EnvironmentWithOptions time.

class IonEnvOptions final
    : public ICoreWebView2EnvironmentOptions,
      public ICoreWebView2EnvironmentOptions2,
      public ICoreWebView2EnvironmentOptions3,
      public ICoreWebView2EnvironmentOptions4,
      public ICoreWebView2EnvironmentOptions5,
      public ICoreWebView2EnvironmentOptions6,
      public ICoreWebView2EnvironmentOptions7,
      public ICoreWebView2EnvironmentOptions8 {
public:
    IonEnvOptions(IonCustomSchemeReg **schemes, UINT32 count)
        : m_refs(1), m_schemes(schemes), m_schemeCount(count) {}

    ~IonEnvOptions() {
        if (m_schemes) {
            for (UINT32 i = 0; i < m_schemeCount; i++) {
                if (m_schemes[i]) m_schemes[i]->Release();
            }
            free(m_schemes);
        }
    }

    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **ppv) override {
        if (!ppv) return E_POINTER;
        if (IsEqualIID(riid, IID_IUnknown) ||
            IsEqualIID(riid, IID_ICoreWebView2EnvironmentOptions)) {
            *ppv = static_cast<ICoreWebView2EnvironmentOptions *>(this);
            AddRef(); return S_OK;
        }
        if (IsEqualIID(riid, IID_ICoreWebView2EnvironmentOptions2)) {
            *ppv = static_cast<ICoreWebView2EnvironmentOptions2 *>(this); AddRef(); return S_OK;
        }
        if (IsEqualIID(riid, IID_ICoreWebView2EnvironmentOptions3)) {
            *ppv = static_cast<ICoreWebView2EnvironmentOptions3 *>(this); AddRef(); return S_OK;
        }
        if (IsEqualIID(riid, IID_ICoreWebView2EnvironmentOptions4)) {
            *ppv = static_cast<ICoreWebView2EnvironmentOptions4 *>(this); AddRef(); return S_OK;
        }
        if (IsEqualIID(riid, IID_ICoreWebView2EnvironmentOptions5)) {
            *ppv = static_cast<ICoreWebView2EnvironmentOptions5 *>(this); AddRef(); return S_OK;
        }
        if (IsEqualIID(riid, IID_ICoreWebView2EnvironmentOptions6)) {
            *ppv = static_cast<ICoreWebView2EnvironmentOptions6 *>(this); AddRef(); return S_OK;
        }
        if (IsEqualIID(riid, IID_ICoreWebView2EnvironmentOptions7)) {
            *ppv = static_cast<ICoreWebView2EnvironmentOptions7 *>(this); AddRef(); return S_OK;
        }
        if (IsEqualIID(riid, IID_ICoreWebView2EnvironmentOptions8)) {
            *ppv = static_cast<ICoreWebView2EnvironmentOptions8 *>(this); AddRef(); return S_OK;
        }
        *ppv = nullptr;
        return E_NOINTERFACE;
    }
    ULONG STDMETHODCALLTYPE AddRef()  override { return (ULONG)InterlockedIncrement(&m_refs); }
    ULONG STDMETHODCALLTYPE Release() override {
        LONG r = InterlockedDecrement(&m_refs);
        if (r == 0) delete this;
        return (ULONG)r;
    }

    // --- v1 methods — defaults (alloc'd "" / FALSE); nullptr triggers E_INVALIDARG.
    HRESULT STDMETHODCALLTYPE get_AdditionalBrowserArguments(LPWSTR *value) override         { if (!value) return E_POINTER; *value = allocEmptyW(); return *value ? S_OK : E_OUTOFMEMORY; }
    HRESULT STDMETHODCALLTYPE put_AdditionalBrowserArguments(LPCWSTR value) override         { (void)value; return S_OK; }
    HRESULT STDMETHODCALLTYPE get_Language(LPWSTR *value) override                            { if (!value) return E_POINTER; *value = allocEmptyW(); return *value ? S_OK : E_OUTOFMEMORY; }
    HRESULT STDMETHODCALLTYPE put_Language(LPCWSTR value) override                            { (void)value; return S_OK; }
    HRESULT STDMETHODCALLTYPE get_TargetCompatibleBrowserVersion(LPWSTR *value) override      { if (!value) return E_POINTER; *value = allocWideCopy(L"130.0.2849.39"); return *value ? S_OK : E_OUTOFMEMORY; }
    HRESULT STDMETHODCALLTYPE put_TargetCompatibleBrowserVersion(LPCWSTR value) override      { (void)value; return S_OK; }
    HRESULT STDMETHODCALLTYPE get_AllowSingleSignOnUsingOSPrimaryAccount(BOOL *value) override{ if (!value) return E_POINTER; *value = FALSE; return S_OK; }
    HRESULT STDMETHODCALLTYPE put_AllowSingleSignOnUsingOSPrimaryAccount(BOOL value) override { (void)value; return S_OK; }

    // --- v2: ExclusiveUserDataFolderAccess ---
    HRESULT STDMETHODCALLTYPE get_ExclusiveUserDataFolderAccess(BOOL *value) override { if (!value) return E_POINTER; *value = FALSE; return S_OK; }
    HRESULT STDMETHODCALLTYPE put_ExclusiveUserDataFolderAccess(BOOL value) override  { (void)value; return S_OK; }

    // --- v3: IsCustomCrashReportingEnabled ---
    HRESULT STDMETHODCALLTYPE get_IsCustomCrashReportingEnabled(BOOL *value) override { if (!value) return E_POINTER; *value = FALSE; return S_OK; }
    HRESULT STDMETHODCALLTYPE put_IsCustomCrashReportingEnabled(BOOL value) override  { (void)value; return S_OK; }

    // --- v5: EnableTrackingPrevention ---
    HRESULT STDMETHODCALLTYPE get_EnableTrackingPrevention(BOOL *value) override { if (!value) return E_POINTER; *value = TRUE; return S_OK; }
    HRESULT STDMETHODCALLTYPE put_EnableTrackingPrevention(BOOL value) override  { (void)value; return S_OK; }

    // --- v6: AreBrowserExtensionsEnabled ---
    HRESULT STDMETHODCALLTYPE get_AreBrowserExtensionsEnabled(BOOL *value) override { if (!value) return E_POINTER; *value = FALSE; return S_OK; }
    HRESULT STDMETHODCALLTYPE put_AreBrowserExtensionsEnabled(BOOL value) override  { (void)value; return S_OK; }

    // --- v7: ChannelSearchKind ---
    HRESULT STDMETHODCALLTYPE get_ChannelSearchKind(COREWEBVIEW2_CHANNEL_SEARCH_KIND *value) override { if (!value) return E_POINTER; *value = COREWEBVIEW2_CHANNEL_SEARCH_KIND_MOST_STABLE; return S_OK; }
    HRESULT STDMETHODCALLTYPE put_ChannelSearchKind(COREWEBVIEW2_CHANNEL_SEARCH_KIND value) override  { (void)value; return S_OK; }
    HRESULT STDMETHODCALLTYPE get_ReleaseChannels(COREWEBVIEW2_RELEASE_CHANNELS *value) override { if (!value) return E_POINTER; *value = COREWEBVIEW2_RELEASE_CHANNELS_STABLE; return S_OK; }
    HRESULT STDMETHODCALLTYPE put_ReleaseChannels(COREWEBVIEW2_RELEASE_CHANNELS value) override  { (void)value; return S_OK; }

    // --- v8: ScrollBarStyle ---
    HRESULT STDMETHODCALLTYPE get_ScrollBarStyle(COREWEBVIEW2_SCROLLBAR_STYLE *value) override { if (!value) return E_POINTER; *value = COREWEBVIEW2_SCROLLBAR_STYLE_DEFAULT; return S_OK; }
    HRESULT STDMETHODCALLTYPE put_ScrollBarStyle(COREWEBVIEW2_SCROLLBAR_STYLE value) override  { (void)value; return S_OK; }

    // --- v4: scheme registrations ---
    HRESULT STDMETHODCALLTYPE GetCustomSchemeRegistrations(
            UINT32 *count, ICoreWebView2CustomSchemeRegistration ***arr) override {
        if (!count || !arr) return E_POINTER;
        if (m_schemeCount == 0) { *count = 0; *arr = nullptr; return S_OK; }
        ICoreWebView2CustomSchemeRegistration **out =
            (ICoreWebView2CustomSchemeRegistration **)CoTaskMemAlloc(
                sizeof(ICoreWebView2CustomSchemeRegistration *) * m_schemeCount);
        if (!out) return E_OUTOFMEMORY;
        for (UINT32 i = 0; i < m_schemeCount; i++) {
            out[i] = m_schemes[i];
            if (out[i]) out[i]->AddRef();
        }
        *count = m_schemeCount;
        *arr = out;
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE SetCustomSchemeRegistrations(
            UINT32 count, ICoreWebView2CustomSchemeRegistration **arr) override {
        (void)count; (void)arr;
        return S_OK;
    }

private:
    LONG m_refs;
    IonCustomSchemeReg **m_schemes;
    UINT32 m_schemeCount;
};

// ---- ionBuildEnvOptions ---------------------------------------------------

ICoreWebView2EnvironmentOptions *ionBuildEnvOptions() {
    int n = ionProtoSchemeCount();
    if (n <= 0) return nullptr;

    IonCustomSchemeReg **regs =
        (IonCustomSchemeReg **)calloc((size_t)n, sizeof(IonCustomSchemeReg *));
    if (!regs) return nullptr;

    UINT32 stored = 0;
    for (int i = 0; i < n; i++) {
        const char *scheme = ionProtoSchemeAt(i);
        if (scheme == nullptr || scheme[0] == 0) continue;
        wchar_t *w = ionUtf8ToWide(scheme);
        if (!w) continue;
        regs[stored++] = new IonCustomSchemeReg(w);
        free(w);
    }

    if (stored == 0) { free(regs); return nullptr; }
    return new IonEnvOptions(regs, stored);
}

// ---- WebResourceRequestedHandler -----------------------------------------
// Fires on every webview request matching a registered scheme. Routes
// through ionProtoLookup (shared with macOS) → builds a response stream
// + Content-Type header → put_Response.

// Strip "scheme://host" prefix from a UTF-8 URL, leaving "/path?q#f" suffix.
// Returns pointer into the input (or "/" if no path component).
static const char *stripSchemeHost(const char *url) {
    if (!url) return "/";
    const char *colon = strstr(url, "://");
    if (!colon) return "/";
    const char *afterAuthority = colon + 3;
    while (*afterAuthority && *afterAuthority != '/'
                            && *afterAuthority != '?' && *afterAuthority != '#') {
        afterAuthority++;
    }
    if (*afterAuthority == 0) return "/";
    return afterAuthority;
}

// Extract scheme (lowercased) into a stack buffer.
static int extractScheme(const char *url, char *out, int cap) {
    if (!url || !out || cap <= 0) return 0;
    const char *colon = strchr(url, ':');
    if (!colon) return 0;
    int n = (int)(colon - url);
    if (n <= 0 || n >= cap) return 0;
    for (int i = 0; i < n; i++) {
        char c = url[i];
        if (c >= 'A' && c <= 'Z') c = (char)(c + ('a' - 'A'));
        out[i] = c;
    }
    out[n] = 0;
    return 1;
}

class WebResourceRequestedHandler final
    : public ICoreWebView2WebResourceRequestedEventHandler {
public:
    WebResourceRequestedHandler() : m_refs(1) {}

    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **ppv) override {
        if (!ppv) return E_POINTER;
        if (IsEqualIID(riid, IID_IUnknown) ||
            IsEqualIID(riid, IID_ICoreWebView2WebResourceRequestedEventHandler)) {
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
            ICoreWebView2WebResourceRequestedEventArgs *args) override {
        (void)sender;
        if (!args) return S_OK;

        ComPtr<ICoreWebView2WebResourceRequest> req;
        if (FAILED(args->get_Request(&req)) || !req) return S_OK;

        LPWSTR uriW = nullptr;
        if (FAILED(req->get_Uri(&uriW)) || !uriW) return S_OK;

        // UTF-16 → UTF-8 for ionProtoLookup. Pessimistic ×4 size.
        char urlU8[2048];
        bool urlOk = ionWideToUtf8(uriW, urlU8, (int)sizeof(urlU8)) != 0;
        CoTaskMemFree(uriW);
        if (!urlOk) return S_OK;

        char scheme[32] = {0};
        if (!extractScheme(urlU8, scheme, (int)sizeof(scheme))) return S_OK;

        const char *rawPath = stripSchemeHost(urlU8);
        unsigned char *body = nullptr;
        size_t bodyLen = 0;
        const char *mime = nullptr;
        int status = 200;

        IonProtoStatus lr = ionProtoLookup(scheme, rawPath, &body, &bodyLen, &mime, &status);
        if (lr == IonProtoNoScheme) {
            // No handler registered for this scheme — let WebView2 decide.
            return S_OK;
        }
        if (!mime) mime = "application/octet-stream";

        WebView2State *st = ionGetWebView2State();
        if (!st || !st->env) {
            if (body) free(body);
            return S_OK;
        }

        // Wrap body bytes in an IStream the response can consume. SHCreateMemStream
        // copies the buffer internally; safe to free our copy after.
        IStream *stream = SHCreateMemStream(body, (UINT)bodyLen);
        if (body) free(body);
        if (!stream) return S_OK;

        // Build Content-Type + permissive CORS so own-scheme fetch() works
        // the same as a real HTTPS origin.
        wchar_t *mimeW = ionUtf8ToWide(mime);
        wchar_t headers[512];
        if (mimeW) {
            _snwprintf_s(headers, sizeof(headers) / sizeof(headers[0]), _TRUNCATE,
                L"Content-Type: %ls\r\nAccess-Control-Allow-Origin: *", mimeW);
            free(mimeW);
        } else {
            wcscpy_s(headers, L"Content-Type: application/octet-stream\r\nAccess-Control-Allow-Origin: *");
        }

        const wchar_t *reason = (status == 200) ? L"OK"
                              : (status == 403) ? L"Forbidden"
                              : (status == 404) ? L"Not Found"
                                                : L"";

        ComPtr<ICoreWebView2WebResourceResponse> response;
        HRESULT hr = st->env->CreateWebResourceResponse(stream, status, reason, headers, &response);
        stream->Release();
        if (FAILED(hr) || !response) return S_OK;

        args->put_Response(response.Get());
        return S_OK;
    }

private:
    LONG m_refs;
};

// ---- ionAttachResourceHandler ---------------------------------------------

HRESULT ionAttachResourceHandler(ICoreWebView2 *webview, EventRegistrationToken *outToken) {
    if (!webview) return E_INVALIDARG;
    int n = ionProtoSchemeCount();
    if (n <= 0) return S_OK;  // nothing registered → no-op

    // Register filter for each scheme's URL space. WebView2 only fires the
    // event for URIs matching at least one filter.
    for (int i = 0; i < n; i++) {
        const char *scheme = ionProtoSchemeAt(i);
        if (!scheme || !scheme[0]) continue;
        // Filter pattern: "<scheme>://*" matches anything in the scheme's URI namespace.
        char patU8[64];
        int written = _snprintf_s(patU8, sizeof(patU8), _TRUNCATE, "%s://*", scheme);
        if (written < 0) continue;
        wchar_t *patW = ionUtf8ToWide(patU8);
        if (!patW) continue;
        webview->AddWebResourceRequestedFilter(patW, COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL);
        free(patW);
    }

    auto *cb = new WebResourceRequestedHandler();
    HRESULT hr = webview->add_WebResourceRequested(cb, outToken);
    cb->Release();
    return hr;
}
