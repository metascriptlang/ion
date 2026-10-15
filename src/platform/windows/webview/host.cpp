#include "internal.hpp"
#include "../internal.h"
#include "../../common/webviewRegistry.h"
extern "C" {
#include "../../bridge.h"
}

#include <ole2.h>
#include <uiautomationcore.h>
#include <uiautomationcoreapi.h>
#include <cstdio>
#include <cwchar>
#include <oleauto.h>
#include <windowsx.h>

using Microsoft::WRL::ComPtr;

static int webviewAt(HWND host, POINT client) {
    int last = ionWebView2PointerTarget(host);
    WebView2State *st = ionWebView2At(last);
    if (st != nullptr && st->visible && PtInRect(&st->bounds, client)) return last;
    int found = ION_WEBVIEW_INVALID;
    for (int id = ion_webview_next(ION_WEBVIEW_INVALID); id != ION_WEBVIEW_INVALID; id = ion_webview_next(id)) {
        st = ionWebView2At(id);
        if (st != nullptr && st->hwnd == host && st->visible && PtInRect(&st->bounds, client)) found = id;
    }
    return found;
}

static ComPtr<ICoreWebView2CompositionController3> composition3(int id) {
    ComPtr<ICoreWebView2CompositionController3> c3;
    WebView2State *st = ionWebView2At(id);
    if (st == nullptr || !st->composition) return c3;
    st->composition->QueryInterface(IID_ICoreWebView2CompositionController3, (void **)&c3);
    return c3;
}

static int toWebview(HWND host, POINTL screen, POINT *out) {
    POINT p = { screen.x, screen.y };
    ScreenToClient(host, &p);
    int id = webviewAt(host, p);
    WebView2State *st = ionWebView2At(id);
    if (st == nullptr) return ION_WEBVIEW_INVALID;
    out->x = p.x - st->bounds.left;
    out->y = p.y - st->bounds.top;
    return id;
}

class HostDropTarget final : public IDropTarget {
public:
    explicit HostDropTarget(HWND host) : m_refs(1), m_host(host) {}

    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **ppv) override {
        if (!ppv) return E_POINTER;
        if (IsEqualIID(riid, IID_IUnknown) || IsEqualIID(riid, IID_IDropTarget)) {
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

    HRESULT STDMETHODCALLTYPE DragEnter(IDataObject *data, DWORD keys, POINTL pt, DWORD *effect) override {
        m_data = data;
        return route(keys, pt, effect);
    }
    HRESULT STDMETHODCALLTYPE DragOver(DWORD keys, POINTL pt, DWORD *effect) override {
        return route(keys, pt, effect);
    }
    HRESULT STDMETHODCALLTYPE DragLeave() override {
        leave();
        m_data.Reset();
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE Drop(IDataObject *data, DWORD keys, POINTL pt, DWORD *effect) override {
        POINT p;
        int id = toWebview(m_host, pt, &p);
        auto c3 = composition3(id);
        HRESULT hr = S_OK;
        if (c3) {
            if (m_target != id) { leave(); c3->DragEnter(data, keys, p, effect); }
            hr = c3->Drop(data, keys, p, effect);
        } else {
            leave();
            *effect = DROPEFFECT_NONE;
        }
        m_target = ION_WEBVIEW_INVALID;
        m_data.Reset();
        return hr;
    }

private:
    HRESULT route(DWORD keys, POINTL pt, DWORD *effect) {
        POINT p;
        int id = toWebview(m_host, pt, &p);
        auto c3 = composition3(id);
        if (!c3) {
            leave();
            *effect = DROPEFFECT_NONE;
            return S_OK;
        }
        if (m_target != id) {
            leave();
            m_target = id;
            return c3->DragEnter(m_data.Get(), keys, p, effect);
        }
        return c3->DragOver(keys, p, effect);
    }

    void leave() {
        if (m_target == ION_WEBVIEW_INVALID) return;
        auto c3 = composition3(m_target);
        m_target = ION_WEBVIEW_INVALID;
        if (c3) c3->DragLeave();
    }

    LONG                 m_refs;
    HWND                 m_host;
    int                  m_target = ION_WEBVIEW_INVALID;
    ComPtr<IDataObject>  m_data;
};

extern "C" void ionWebView2RegisterDrop(HWND host) {
    auto *target = new HostDropTarget(host);
    HRESULT hr = RegisterDragDrop(host, target);
    target->Release();
    if (FAILED(hr))
        fprintf(stderr, "[ion] RegisterDragDrop failed: 0x%08lx (OleInitialize on this thread?)\n", (long)hr);
}

extern "C" void ionWebView2RevokeDrop(HWND host) {
    RevokeDragDrop(host);
}


struct BrowserWindowSearch {
    DWORD pid;
    RECT  frame;
    HWND  found;
};

static BOOL CALLBACK findBrowserWindow(HWND hwnd, LPARAM arg) {
    BrowserWindowSearch *s = (BrowserWindowSearch *)arg;
    DWORD pid = 0;
    GetWindowThreadProcessId(hwnd, &pid);
    if (pid != s->pid || !IsWindowVisible(hwnd)) return TRUE;
    wchar_t cls[64];
    if (GetClassNameW(hwnd, cls, 64) <= 0 || wcscmp(cls, L"Chrome_WidgetWin_1") != 0) return TRUE;
    RECT r, overlap;
    GetWindowRect(hwnd, &r);
    if (!IntersectRect(&overlap, &r, &s->frame)) return TRUE;
    s->found = hwnd;
    return FALSE;
}

// With a CompositionController the page's UIA tree lives on a top-level
// Chrome_WidgetWin_1 popup of the WebView2 browser process placed over the
// webview frame (measured 2026-09-23, WebView2 Runtime 153.0.4234.48); no Ion window parents it.
static HWND browserWindow(HWND host, int id);

static int nextWebview(HWND host, int from, int step) {
    for (int id = from + step; id >= 0 && id < ION_MAX_WEBVIEWS; id += step)
        if (browserWindow(host, id) != nullptr) return id;
    return ION_WEBVIEW_INVALID;
}

static HWND browserWindow(HWND host, int id) {
    WebView2State *st = ionWebView2At(id);
    if (st == nullptr || st->hwnd != host || !st->webview) return nullptr;
    UINT32 pid = 0;
    if (FAILED(st->webview->get_BrowserProcessId(&pid)) || pid == 0) return nullptr;
    POINT tl = { st->bounds.left, st->bounds.top };
    ClientToScreen(host, &tl);
    BrowserWindowSearch s = { pid, { tl.x, tl.y, tl.x + 1, tl.y + 1 }, nullptr };
    EnumWindows(findBrowserWindow, (LPARAM)&s);
    return s.found;
}

class WebviewUiaElement final : public IRawElementProviderSimple, public IRawElementProviderFragment {
public:
    WebviewUiaElement(IRawElementProviderFragmentRoot *root, HWND host, int id)
        : m_refs(1), m_root(root), m_host(host), m_id(id) { m_root->AddRef(); }
    ~WebviewUiaElement() { m_root->Release(); }

    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **ppv) override {
        if (!ppv) return E_POINTER;
        if (IsEqualIID(riid, IID_IUnknown) || IsEqualIID(riid, IID_IRawElementProviderSimple)) {
            *ppv = static_cast<IRawElementProviderSimple *>(this);
        } else if (IsEqualIID(riid, IID_IRawElementProviderFragment)) {
            *ppv = static_cast<IRawElementProviderFragment *>(this);
        } else {
            *ppv = nullptr;
            return E_NOINTERFACE;
        }
        AddRef();
        return S_OK;
    }
    ULONG STDMETHODCALLTYPE AddRef()  override { return (ULONG)InterlockedIncrement(&m_refs); }
    ULONG STDMETHODCALLTYPE Release() override {
        LONG r = InterlockedDecrement(&m_refs);
        if (r == 0) delete this;
        return (ULONG)r;
    }

    HRESULT STDMETHODCALLTYPE get_ProviderOptions(ProviderOptions *out) override {
        *out = (ProviderOptions)(ProviderOptions_ServerSideProvider | ProviderOptions_UseComThreading);
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE GetPatternProvider(PATTERNID, IUnknown **out) override {
        *out = nullptr;
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE GetPropertyValue(PROPERTYID, VARIANT *out) override {
        out->vt = VT_EMPTY;
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE get_HostRawElementProvider(IRawElementProviderSimple **out) override {
        *out = nullptr;
        HWND browser = browserWindow(m_host, m_id);
        return browser ? UiaHostProviderFromHwnd(browser, out) : S_OK;
    }

    HRESULT STDMETHODCALLTYPE Navigate(NavigateDirection direction, IRawElementProviderFragment **out) override {
        *out = nullptr;
        if (direction == NavigateDirection_Parent)
            return m_root->QueryInterface(IID_IRawElementProviderFragment, (void **)out);
        int sibling = direction == NavigateDirection_NextSibling ? nextWebview(m_host, m_id, 1)
                    : direction == NavigateDirection_PreviousSibling ? nextWebview(m_host, m_id, -1)
                    : ION_WEBVIEW_INVALID;
        if (sibling != ION_WEBVIEW_INVALID) *out = new WebviewUiaElement(m_root, m_host, sibling);
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE GetRuntimeId(SAFEARRAY **out) override {
        int id[] = { UiaAppendRuntimeId, m_id + 1 };
        *out = SafeArrayCreateVector(VT_I4, 0, 2);
        if (*out == nullptr) return E_OUTOFMEMORY;
        for (LONG i = 0; i < 2; i++) SafeArrayPutElement(*out, &i, &id[i]);
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE get_BoundingRectangle(UiaRect *out) override {
        *out = UiaRect{ 0, 0, 0, 0 };
        HWND browser = browserWindow(m_host, m_id);
        RECT r;
        if (browser && GetWindowRect(browser, &r))
            *out = UiaRect{ (double)r.left, (double)r.top, (double)(r.right - r.left), (double)(r.bottom - r.top) };
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE GetEmbeddedFragmentRoots(SAFEARRAY **out) override {
        *out = nullptr;
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE SetFocus() override {
        ionWebviewFocus(m_id);
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE get_FragmentRoot(IRawElementProviderFragmentRoot **out) override {
        *out = m_root;
        m_root->AddRef();
        return S_OK;
    }

private:
    LONG                             m_refs;
    IRawElementProviderFragmentRoot *m_root;
    HWND                             m_host;
    int                              m_id;
};

class HostUiaProvider final : public IRawElementProviderSimple,
                              public IRawElementProviderFragment,
                              public IRawElementProviderFragmentRoot {
public:
    explicit HostUiaProvider(HWND host) : m_refs(1), m_host(host) {}

    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **ppv) override {
        if (!ppv) return E_POINTER;
        if (IsEqualIID(riid, IID_IUnknown) || IsEqualIID(riid, IID_IRawElementProviderSimple)) {
            *ppv = static_cast<IRawElementProviderSimple *>(this);
        } else if (IsEqualIID(riid, IID_IRawElementProviderFragment)) {
            *ppv = static_cast<IRawElementProviderFragment *>(this);
        } else if (IsEqualIID(riid, IID_IRawElementProviderFragmentRoot)) {
            *ppv = static_cast<IRawElementProviderFragmentRoot *>(this);
        } else {
            *ppv = nullptr;
            return E_NOINTERFACE;
        }
        AddRef();
        return S_OK;
    }
    ULONG STDMETHODCALLTYPE AddRef()  override { return (ULONG)InterlockedIncrement(&m_refs); }
    ULONG STDMETHODCALLTYPE Release() override {
        LONG r = InterlockedDecrement(&m_refs);
        if (r == 0) delete this;
        return (ULONG)r;
    }

    HRESULT STDMETHODCALLTYPE get_ProviderOptions(ProviderOptions *out) override {
        *out = (ProviderOptions)(ProviderOptions_ServerSideProvider | ProviderOptions_UseComThreading);
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE GetPatternProvider(PATTERNID, IUnknown **out) override {
        *out = nullptr;
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE GetPropertyValue(PROPERTYID, VARIANT *out) override {
        out->vt = VT_EMPTY;
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE get_HostRawElementProvider(IRawElementProviderSimple **out) override {
        return UiaHostProviderFromHwnd(m_host, out);
    }

    HRESULT STDMETHODCALLTYPE Navigate(NavigateDirection direction, IRawElementProviderFragment **out) override {
        *out = nullptr;
        if (direction == NavigateDirection_FirstChild) return webview(nextWebview(m_host, -1, 1), out);
        if (direction == NavigateDirection_LastChild) return webview(nextWebview(m_host, ION_MAX_WEBVIEWS, -1), out);
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE GetRuntimeId(SAFEARRAY **out) override {
        *out = nullptr;
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE get_BoundingRectangle(UiaRect *out) override {
        *out = UiaRect{ 0, 0, 0, 0 };
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE GetEmbeddedFragmentRoots(SAFEARRAY **out) override {
        *out = nullptr;
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE SetFocus() override { return S_OK; }
    HRESULT STDMETHODCALLTYPE get_FragmentRoot(IRawElementProviderFragmentRoot **out) override {
        *out = static_cast<IRawElementProviderFragmentRoot *>(this);
        AddRef();
        return S_OK;
    }

    HRESULT STDMETHODCALLTYPE ElementProviderFromPoint(double x, double y, IRawElementProviderFragment **out) override {
        *out = nullptr;
        POINT p = { (LONG)x, (LONG)y };
        ScreenToClient(m_host, &p);
        return webview(webviewAt(m_host, p), out);
    }
    HRESULT STDMETHODCALLTYPE GetFocus(IRawElementProviderFragment **out) override {
        *out = nullptr;
        return S_OK;
    }

private:
    HRESULT webview(int id, IRawElementProviderFragment **out) {
        if (browserWindow(m_host, id) == nullptr) return S_OK;
        *out = new WebviewUiaElement(this, m_host, id);
        return S_OK;
    }

    LONG m_refs;
    HWND m_host;
};

extern "C" int ionWebView2HostAutomation(HWND host, void **provider, WPARAM wParam, LPARAM lParam, LRESULT *result) {
    if ((LONG)lParam != UiaRootObjectId) return 0;
    if (*provider == nullptr) *provider = new HostUiaProvider(host);
    *result = UiaReturnRawElementProvider(host, wParam, lParam, static_cast<HostUiaProvider *>(*provider));
    return 1;
}

extern "C" void ionWebView2DetachAutomation(HWND host, void **provider) {
    auto *uia = static_cast<HostUiaProvider *>(*provider);
    if (uia == nullptr) return;
    UiaReturnRawElementProvider(host, 0, 0, nullptr);
    UiaDisconnectProvider(uia);
    uia->Release();
    *provider = nullptr;
}
