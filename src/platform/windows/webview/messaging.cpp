// Ion Windows — WebMessageReceived handler.
//
// Mirrors mac's IonMessageHandler in webview/bootstrap.m. JS calls
// `window.chrome.webview.postMessage(envelope)` (via the bootstrap shim
// from common/bootstrap.c). WebView2 fires WebMessageReceived with the
// envelope serialized to JSON. We:
//   1. Parse the JSON to extract `__key`, `name`, `payload` (string fields).
//   2. Verify __key via ion_invoke_key_verify (drop on mismatch — defense
//      against scripts injected outside our bootstrap closure).
//   3. ionEnqueueMessage(name, payload) → MS-side listen() picks it up.
//
// JSON parsing: hand-rolled minimal extractor. We only need 3 fixed string
// fields with a known shape (matches bootstrap.c's `{__key, name, payload}`
// envelope). No need for a full parser; the bootstrap closure is the only
// thing that can produce the JSON that ion accepts (invoke_key gate).

#include "internal.hpp"
#include "../../common/invokekey.h"
#include "../../common/protocol.h"
#include "../../common/json_extract.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>

class MessageReceivedCallback final
    : public ICoreWebView2WebMessageReceivedEventHandler {
public:
    MessageReceivedCallback() : m_refs(1) {}

    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **ppv) override {
        if (!ppv) return E_POINTER;
        if (IsEqualIID(riid, IID_IUnknown) ||
            IsEqualIID(riid, IID_ICoreWebView2WebMessageReceivedEventHandler)) {
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
                                     ICoreWebView2WebMessageReceivedEventArgs *args) override {
        (void)sender;
        if (args == nullptr) return S_OK;

        LPWSTR jsonW = nullptr;
        if (FAILED(args->get_WebMessageAsJson(&jsonW)) || jsonW == nullptr) return S_OK;

        // UTF-16 → UTF-8. Envelope is small (key + name + payload) but payload
        // can be arbitrarily long — allocate per-message rather than using a
        // fixed stack buffer.
        int needed = WideCharToMultiByte(CP_UTF8, 0, jsonW, -1, NULL, 0, NULL, NULL);
        if (needed <= 0) { CoTaskMemFree(jsonW); return S_OK; }
        char *jsonU8 = (char *)malloc((size_t)needed);
        if (jsonU8 == nullptr) { CoTaskMemFree(jsonW); return S_OK; }
        if (WideCharToMultiByte(CP_UTF8, 0, jsonW, -1, jsonU8, needed, NULL, NULL) <= 0) {
            free(jsonU8); CoTaskMemFree(jsonW); return S_OK;
        }
        CoTaskMemFree(jsonW);

        char *invokeKey = ion_json_extract_string(jsonU8, ION_FIELD_KEY);
        if (invokeKey == nullptr || !ion_invoke_key_verify(invokeKey)) {
            // Same wording as mac NSLog for parity / grep-ability.
            fprintf(stderr, "[ion] IPC rejected: invalid invoke_key\n");
            free(invokeKey);
            free(jsonU8);
            return S_OK;
        }
        free(invokeKey);

        char *name    = ion_json_extract_string(jsonU8, "name");
        char *payload = ion_json_extract_string(jsonU8, "payload");
        if (name != nullptr) {
            ionEnqueueMessage(name, payload ? payload : "");
        }
        free(name);
        free(payload);
        free(jsonU8);
        return S_OK;
    }

private:
    LONG m_refs;
};

HRESULT ionAttachMessageHandler(ICoreWebView2 *webview, EventRegistrationToken *outToken) {
    if (webview == nullptr) return E_INVALIDARG;
    auto *cb = new MessageReceivedCallback();
    HRESULT hr = webview->add_WebMessageReceived(cb, outToken);
    cb->Release();
    return hr;
}
