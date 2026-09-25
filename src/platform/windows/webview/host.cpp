#include "internal.hpp"
#include "../internal.h"

#include <ole2.h>
#include <uiautomationcore.h>
#include <uiautomationcoreapi.h>
#include <cstdio>
#include <cwchar>
#include <oleauto.h>
#include <windowsx.h>

using Microsoft::WRL::ComPtr;

static ComPtr<ICoreWebView2CompositionController3> composition3() {
    ComPtr<ICoreWebView2CompositionController3> c3;
    WebView2State *st = ionGetWebView2State();
    if (st == nullptr || !st->composition) return c3;
    st->composition->QueryInterface(IID_ICoreWebView2CompositionController3, (void **)&c3);
    return c3;
}

static bool toWebview(HWND host, POINTL screen, POINT *out) {
    POINT p = { screen.x, screen.y };
    ScreenToClient(host, &p);
    if (ionCompRoute(p.x, p.y) != ION_COMP_ROUTE_WEBVIEW) return false;
    int ox, oy;
    ionCompWebviewOrigin(&ox, &oy);
    out->x = p.x - ox;
    out->y = p.y - oy;
    return true;
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
        auto c3 = composition3();
        HRESULT hr = S_OK;
        if (c3 && toWebview(m_host, pt, &p)) {
            if (!m_inWebview) c3->DragEnter(data, keys, p, effect);
            hr = c3->Drop(data, keys, p, effect);
        } else {
            leave();
            *effect = DROPEFFECT_NONE;
        }
        m_inWebview = false;
        m_data.Reset();
        return hr;
    }

private:
    HRESULT route(DWORD keys, POINTL pt, DWORD *effect) {
        POINT p;
        auto c3 = composition3();
        if (!c3 || !toWebview(m_host, pt, &p)) {
            leave();
            *effect = DROPEFFECT_NONE;
            return S_OK;
        }
        if (!m_inWebview) {
            m_inWebview = true;
            return c3->DragEnter(m_data.Get(), keys, p, effect);
        }
        return c3->DragOver(keys, p, effect);
    }

    void leave() {
        if (!m_inWebview) return;
        m_inWebview = false;
        auto c3 = composition3();
        if (c3) c3->DragLeave();
    }

    LONG                 m_refs;
    HWND                 m_host;
    bool                 m_inWebview = false;
    ComPtr<IDataObject>  m_data;
};

static HostDropTarget *s_dropTarget = nullptr;

static const int ION_MAX_POINTERS = 16;
static UINT32 s_webviewPointers[ION_MAX_POINTERS];
static int    s_webviewPointerCount = 0;

static bool pointerInWebview(UINT32 id) {
    for (int i = 0; i < s_webviewPointerCount; i++)
        if (s_webviewPointers[i] == id) return true;
    return false;
}

static void trackPointer(UINT32 id, bool on) {
    for (int i = 0; i < s_webviewPointerCount; i++) {
        if (s_webviewPointers[i] != id) continue;
        if (!on) s_webviewPointers[i] = s_webviewPointers[--s_webviewPointerCount];
        return;
    }
    if (on && s_webviewPointerCount < ION_MAX_POINTERS) s_webviewPointers[s_webviewPointerCount++] = id;
}

static POINT toFrame(HWND host, POINT screen) {
    int ox, oy;
    ionCompWebviewOrigin(&ox, &oy);
    ScreenToClient(host, &screen);
    screen.x -= ox;
    screen.y -= oy;
    return screen;
}

static RECT toFrameRect(HWND host, RECT r) {
    POINT tl = toFrame(host, POINT{ r.left, r.top });
    POINT br = toFrame(host, POINT{ r.right, r.bottom });
    return RECT{ tl.x, tl.y, br.x, br.y };
}

static HRESULT fillPointerInfo(HWND host, UINT32 id, ICoreWebView2PointerInfo *out) {
    POINTER_INFO pi;
    if (!GetPointerInfo(id, &pi)) return HRESULT_FROM_WIN32(GetLastError());
    out->put_PointerKind(pi.pointerType);
    out->put_PointerId(pi.pointerId);
    out->put_FrameId(pi.frameId);
    out->put_PointerFlags(pi.pointerFlags);
    RECT device, display;
    if (GetPointerDeviceRects(pi.sourceDevice, &device, &display)) {
        out->put_PointerDeviceRect(device);
        out->put_DisplayRect(display);
    }
    out->put_PixelLocation(toFrame(host, pi.ptPixelLocation));
    out->put_PixelLocationRaw(toFrame(host, pi.ptPixelLocationRaw));
    out->put_HimetricLocation(pi.ptHimetricLocation);
    out->put_HimetricLocationRaw(pi.ptHimetricLocationRaw);
    out->put_Time(pi.dwTime);
    out->put_HistoryCount(pi.historyCount);
    out->put_InputData(pi.InputData);
    out->put_KeyStates(pi.dwKeyStates);
    out->put_PerformanceCount(pi.PerformanceCount);
    out->put_ButtonChangeKind((INT32)pi.ButtonChangeType);
    if (pi.pointerType == PT_PEN) {
        POINTER_PEN_INFO pen;
        if (GetPointerPenInfo(id, &pen)) {
            out->put_PenFlags(pen.penFlags);
            out->put_PenMask(pen.penMask);
            out->put_PenPressure(pen.pressure);
            out->put_PenRotation(pen.rotation);
            out->put_PenTiltX(pen.tiltX);
            out->put_PenTiltY(pen.tiltY);
        }
    } else if (pi.pointerType == PT_TOUCH) {
        POINTER_TOUCH_INFO touch;
        if (GetPointerTouchInfo(id, &touch)) {
            out->put_TouchFlags(touch.touchFlags);
            out->put_TouchMask(touch.touchMask);
            out->put_TouchContact(toFrameRect(host, touch.rcContact));
            out->put_TouchContactRaw(toFrameRect(host, touch.rcContactRaw));
            out->put_TouchOrientation(touch.orientation);
            out->put_TouchPressure(touch.pressure);
        }
    }
    return S_OK;
}

extern "C" int ionWebView2PointerMessage(HWND host, UINT msg, WPARAM wParam, LPARAM lParam) {
    WebView2State *st = ionGetWebView2State();
    if (st == nullptr || !st->composition || !st->env) return 0;
    UINT32 id = GET_POINTERID_WPARAM(wParam);
    POINT pt = { GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam) };
    ScreenToClient(host, &pt);
    bool started = pointerInWebview(id);
    if (!started && ionCompRoute(pt.x, pt.y) != ION_COMP_ROUTE_WEBVIEW) return 0;
    if (msg == WM_POINTERDOWN || msg == WM_POINTERENTER) trackPointer(id, true);
    if (msg == WM_POINTERDOWN) ionWebView2Focus();

    ComPtr<ICoreWebView2Environment3> env3;
    ComPtr<ICoreWebView2PointerInfo> info;
    if (FAILED(st->env->QueryInterface(IID_ICoreWebView2Environment3, (void **)&env3)) ||
        FAILED(env3->CreateCoreWebView2PointerInfo(&info)) ||
        FAILED(fillPointerInfo(host, id, info.Get()))) return 0;
    st->composition->SendPointerInput((COREWEBVIEW2_POINTER_EVENT_KIND)msg, info.Get());

    if (msg == WM_POINTERUP || msg == WM_POINTERLEAVE || msg == WM_POINTERCAPTURECHANGED) {
        POINTER_INFO pi;
        if (msg != WM_POINTERUP || !GetPointerInfo(id, &pi) || !(pi.pointerFlags & POINTER_FLAG_INRANGE))
            trackPointer(id, false);
    }
    return 1;
}

extern "C" void ionWebView2RegisterDrop(HWND host) {
    if (s_dropTarget != nullptr) return;
    s_dropTarget = new HostDropTarget(host);
    HRESULT hr = RegisterDragDrop(host, s_dropTarget);
    if (FAILED(hr)) {
        fprintf(stderr, "[ion] RegisterDragDrop failed: 0x%08lx (OleInitialize on this thread?)\n", (long)hr);
        s_dropTarget->Release();
        s_dropTarget = nullptr;
    }
}

extern "C" void ionWebView2RevokeDrop(HWND host) {
    if (s_dropTarget == nullptr) return;
    RevokeDragDrop(host);
    s_dropTarget->Release();
    s_dropTarget = nullptr;
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
static HWND browserWindow(HWND host) {
    WebView2State *st = ionGetWebView2State();
    if (st == nullptr || !st->webview) return nullptr;
    UINT32 pid = 0;
    if (FAILED(st->webview->get_BrowserProcessId(&pid)) || pid == 0) return nullptr;
    int ox, oy;
    ionCompWebviewOrigin(&ox, &oy);
    RECT client;
    GetClientRect(host, &client);
    POINT tl = { ox, oy };
    ClientToScreen(host, &tl);
    BrowserWindowSearch s = { pid, { tl.x, tl.y, tl.x + 1, tl.y + 1 }, nullptr };
    EnumWindows(findBrowserWindow, (LPARAM)&s);
    return s.found;
}

class WebviewUiaElement final : public IRawElementProviderSimple, public IRawElementProviderFragment {
public:
    WebviewUiaElement(IRawElementProviderFragmentRoot *root, HWND host) : m_refs(1), m_root(root), m_host(host) {}

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
        HWND browser = browserWindow(m_host);
        return browser ? UiaHostProviderFromHwnd(browser, out) : S_OK;
    }

    HRESULT STDMETHODCALLTYPE Navigate(NavigateDirection direction, IRawElementProviderFragment **out) override {
        *out = nullptr;
        if (direction == NavigateDirection_Parent)
            return m_root->QueryInterface(IID_IRawElementProviderFragment, (void **)out);
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE GetRuntimeId(SAFEARRAY **out) override {
        int id[] = { UiaAppendRuntimeId, 1 };
        *out = SafeArrayCreateVector(VT_I4, 0, 2);
        if (*out == nullptr) return E_OUTOFMEMORY;
        for (LONG i = 0; i < 2; i++) SafeArrayPutElement(*out, &i, &id[i]);
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE get_BoundingRectangle(UiaRect *out) override {
        *out = UiaRect{ 0, 0, 0, 0 };
        HWND browser = browserWindow(m_host);
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
        ionWebView2Focus();
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
};

class HostUiaProvider final : public IRawElementProviderSimple,
                              public IRawElementProviderFragment,
                              public IRawElementProviderFragmentRoot {
public:
    explicit HostUiaProvider(HWND host) : m_refs(1), m_host(host) {}
    ~HostUiaProvider() { if (m_webview) m_webview->Release(); }

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
        if (direction != NavigateDirection_FirstChild && direction != NavigateDirection_LastChild) return S_OK;
        return webview(out);
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
        if (ionCompRoute(p.x, p.y) != ION_COMP_ROUTE_WEBVIEW) return S_OK;
        return webview(out);
    }
    HRESULT STDMETHODCALLTYPE GetFocus(IRawElementProviderFragment **out) override {
        *out = nullptr;
        return S_OK;
    }

private:
    HRESULT webview(IRawElementProviderFragment **out) {
        if (browserWindow(m_host) == nullptr) return S_OK;
        if (m_webview == nullptr) m_webview = new WebviewUiaElement(this, m_host);
        *out = m_webview;
        m_webview->AddRef();
        return S_OK;
    }

    LONG               m_refs;
    HWND               m_host;
    WebviewUiaElement *m_webview = nullptr;
};

static HostUiaProvider *s_uiaProvider = nullptr;

extern "C" int ionWebView2HostAutomation(HWND host, WPARAM wParam, LPARAM lParam, LRESULT *result) {
    if ((LONG)lParam != UiaRootObjectId) return 0;
    if (s_uiaProvider == nullptr) s_uiaProvider = new HostUiaProvider(host);
    *result = UiaReturnRawElementProvider(host, wParam, lParam, s_uiaProvider);
    return 1;
}

extern "C" void ionWebView2DetachAutomation(HWND host) {
    if (s_uiaProvider == nullptr) return;
    UiaReturnRawElementProvider(host, 0, 0, nullptr);
    UiaDisconnectProvider(s_uiaProvider);
    s_uiaProvider->Release();
    s_uiaProvider = nullptr;
}
