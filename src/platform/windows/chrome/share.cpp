// Ion Windows — share picker: the WinRT DataTransferManager of the active window, reached
// through IDataTransferManagerInterop (Windows 10+).

#include "../utf8.h"
extern "C" {
#include "../../bridge.h"
}

#include <windows.h>
#include <inspectable.h>
#include <hstring.h>
#include <cstdlib>
#include <cstring>

// mingw ships no WinRT DataTransfer headers: these vtables keep the slot order and IIDs of
// windows-rs 0.62.2 (Windows/ApplicationModel/DataTransfer/mod.rs); a reordered slot calls the wrong method.
static const GUID kInteropIid   = {0x3a3dcd6c, 0x3eab, 0x43dc, {0xbc, 0xde, 0x45, 0x67, 0x1c, 0xe8, 0x00, 0xc8}};
static const GUID kManagerIid   = {0xa5caee9b, 0x8708, 0x49d1, {0x8d, 0x36, 0x67, 0xd2, 0x5a, 0x8d, 0xa0, 0x0c}};
static const GUID kPackage2Iid  = {0x041c1fe9, 0x2409, 0x45e1, {0xa5, 0x38, 0x4c, 0x53, 0xee, 0xee, 0x04, 0xa7}};
static const GUID kUriFactoryIid = {0x44a9796f, 0x723e, 0x4fdf, {0xa2, 0x18, 0x03, 0x3e, 0x75, 0xb0, 0xc0, 0x84}};
// TypedEventHandler<DataTransferManager, DataRequestedEventArgs>, the pinterface IID derived from its signature.
static const GUID kHandlerIid   = {0xec6f9cc8, 0x46d0, 0x5e0e, {0xb4, 0xd2, 0x7d, 0x77, 0x73, 0xae, 0x37, 0xa0}};

struct IDataTransferManagerInteropAbi : IUnknown {
    virtual HRESULT STDMETHODCALLTYPE GetForWindow(HWND window, REFIID riid, void **manager) = 0;
    virtual HRESULT STDMETHODCALLTYPE ShowShareUIForWindow(HWND window) = 0;
};

struct IDataPackagePropertySetAbi : IInspectable {
    virtual HRESULT STDMETHODCALLTYPE get_Title(HSTRING *value) = 0;
    virtual HRESULT STDMETHODCALLTYPE put_Title(HSTRING value) = 0;
};

struct IDataPackageAbi : IInspectable {
    virtual HRESULT STDMETHODCALLTYPE GetView(void **view) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_Properties(IDataPackagePropertySetAbi **value) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_RequestedOperation(INT32 *value) = 0;
    virtual HRESULT STDMETHODCALLTYPE put_RequestedOperation(INT32 value) = 0;
    virtual HRESULT STDMETHODCALLTYPE add_OperationCompleted(IUnknown *handler, INT64 *token) = 0;
    virtual HRESULT STDMETHODCALLTYPE remove_OperationCompleted(INT64 token) = 0;
    virtual HRESULT STDMETHODCALLTYPE add_Destroyed(IUnknown *handler, INT64 *token) = 0;
    virtual HRESULT STDMETHODCALLTYPE remove_Destroyed(INT64 token) = 0;
    virtual HRESULT STDMETHODCALLTYPE SetData(HSTRING format, IInspectable *value) = 0;
    virtual HRESULT STDMETHODCALLTYPE SetDataProvider(HSTRING format, IUnknown *provider) = 0;
    virtual HRESULT STDMETHODCALLTYPE SetText(HSTRING value) = 0;
};

struct IDataPackage2Abi : IInspectable {
    virtual HRESULT STDMETHODCALLTYPE SetApplicationLink(IInspectable *uri) = 0;
    virtual HRESULT STDMETHODCALLTYPE SetWebLink(IInspectable *uri) = 0;
};

struct IDataRequestAbi : IInspectable {
    virtual HRESULT STDMETHODCALLTYPE get_Data(IDataPackageAbi **value) = 0;
};

struct IDataRequestedEventArgsAbi : IInspectable {
    virtual HRESULT STDMETHODCALLTYPE get_Request(IDataRequestAbi **value) = 0;
};

struct IDataTransferManagerAbi : IInspectable {
    virtual HRESULT STDMETHODCALLTYPE add_DataRequested(IUnknown *handler, INT64 *token) = 0;
    virtual HRESULT STDMETHODCALLTYPE remove_DataRequested(INT64 token) = 0;
};

struct IUriRuntimeClassFactoryAbi : IInspectable {
    virtual HRESULT STDMETHODCALLTYPE CreateUri(HSTRING uri, IInspectable **instance) = 0;
};

typedef HRESULT (WINAPI *RoGetActivationFactoryFn)(HSTRING, REFIID, void **);
typedef HRESULT (WINAPI *WindowsCreateStringFn)(PCWSTR, UINT32, HSTRING *);
typedef HRESULT (WINAPI *WindowsDeleteStringFn)(HSTRING);

struct WinRt {
    RoGetActivationFactoryFn activationFactory;
    WindowsCreateStringFn    createString;
    WindowsDeleteStringFn    deleteString;
};

template <class F> static F proc(HMODULE m, const char *name) {
    return reinterpret_cast<F>(reinterpret_cast<void *>(GetProcAddress(m, name)));
}

static const WinRt *winrt(void) {
    static WinRt api = {};
    static bool loaded = false;
    if (!loaded) {
        loaded = true;
        HMODULE m = LoadLibraryW(L"combase.dll");
        if (m != nullptr) {
            api.activationFactory = proc<RoGetActivationFactoryFn>(m, "RoGetActivationFactory");
            api.createString = proc<WindowsCreateStringFn>(m, "WindowsCreateString");
            api.deleteString = proc<WindowsDeleteStringFn>(m, "WindowsDeleteString");
        }
    }
    return api.activationFactory && api.createString && api.deleteString ? &api : nullptr;
}

struct HStr {
    HSTRING h = nullptr;
    explicit HStr(const char *utf8) {
        wchar_t *wide = ionUtf8ToWide(utf8);
        if (wide != nullptr) {
            winrt()->createString(wide, (UINT32)wcslen(wide), &h);
            free(wide);
        }
    }
    ~HStr() { if (h != nullptr) winrt()->deleteString(h); }
};

template <class T> static void release(T *&p) {
    if (p) { p->Release(); p = nullptr; }
}

static char *s_title = nullptr;
static char *s_text  = nullptr;
static char *s_url   = nullptr;

static void keep(char *&slot, const char *value) {
    free(slot);
    slot = _strdup(value);
}

static void fill(IDataPackageAbi *pkg) {
    IDataPackagePropertySetAbi *props = nullptr;
    const char *title = s_title[0] ? s_title : s_text[0] ? s_text : s_url;
    if (SUCCEEDED(pkg->get_Properties(&props))) {
        HStr t(title);
        props->put_Title(t.h);
        release(props);
    }
    if (s_text[0]) {
        HStr t(s_text);
        pkg->SetText(t.h);
    }
    if (s_url[0]) {
        HStr cls("Windows.Foundation.Uri");
        HStr u(s_url);
        IUriRuntimeClassFactoryAbi *factory = nullptr;
        IDataPackage2Abi *pkg2 = nullptr;
        IInspectable *uri = nullptr;
        if (SUCCEEDED(winrt()->activationFactory(cls.h, kUriFactoryIid, (void **)&factory))
            && SUCCEEDED(factory->CreateUri(u.h, &uri))
            && SUCCEEDED(pkg->QueryInterface(kPackage2Iid, (void **)&pkg2))) {
            pkg2->SetWebLink(uri);
        }
        release(pkg2);
        release(uri);
        release(factory);
    }
}

struct DataRequestedHandler : IUnknown {
    LONG refs = 1;

    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **out) override {
        if (riid == IID_IUnknown || riid == IID_IAgileObject || riid == kHandlerIid) {
            *out = this;
            AddRef();
            return S_OK;
        }
        *out = nullptr;
        return E_NOINTERFACE;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return (ULONG)InterlockedIncrement(&refs); }
    ULONG STDMETHODCALLTYPE Release() override {
        LONG n = InterlockedDecrement(&refs);
        if (n == 0) delete this;
        return (ULONG)n;
    }
    virtual HRESULT STDMETHODCALLTYPE Invoke(IInspectable *sender, IDataRequestedEventArgsAbi *args) {
        (void)sender;
        IDataRequestAbi *request = nullptr;
        IDataPackageAbi *pkg = nullptr;
        if (SUCCEEDED(args->get_Request(&request)) && SUCCEEDED(request->get_Data(&pkg))) fill(pkg);
        release(pkg);
        release(request);
        return S_OK;
    }
};

static IDataTransferManagerAbi *s_manager = nullptr;
static INT64 s_token = 0;

int ionShare(const char *title, const char *text, const char *url) {
    HWND hwnd = GetActiveWindow();
    if (hwnd == nullptr) return ION_SERVICE_NO_WINDOW;
    if (!text[0] && !url[0]) return ION_SERVICE_REFUSED;
    const WinRt *api = winrt();
    if (api == nullptr) return ION_SERVICE_UNSUPPORTED;
    keep(s_title, title);
    keep(s_text, text);
    keep(s_url, url);

    if (s_manager != nullptr) {
        s_manager->remove_DataRequested(s_token);
        release(s_manager);
    }
    HStr cls("Windows.ApplicationModel.DataTransfer.DataTransferManager");
    IDataTransferManagerInteropAbi *interop = nullptr;
    HRESULT hr = api->activationFactory(cls.h, kInteropIid, (void **)&interop);
    if (FAILED(hr)) return ION_SERVICE_UNSUPPORTED;
    hr = interop->GetForWindow(hwnd, kManagerIid, (void **)&s_manager);
    if (SUCCEEDED(hr)) {
        DataRequestedHandler *handler = new DataRequestedHandler();
        hr = s_manager->add_DataRequested(handler, &s_token);
        handler->Release();
    }
    if (SUCCEEDED(hr)) hr = interop->ShowShareUIForWindow(hwnd);
    release(interop);
    return SUCCEEDED(hr) ? ION_SERVICE_DONE : ION_SERVICE_REFUSED;
}
