// Each callback class is a hand-rolled IUnknown impl (zig's bundled MinGW
// ships wrl/client.h for ComPtr but NOT wrl/event.h for Callback<>).

#include "internal.hpp"
#include "../utf8.h"
#include "../internal.h"
#include "../../common/invokekey.h"
#include "../../common/bootstrap.h"
#include "../../common/protoReg.h"
#include "../../common/webviewRegistry.h"
extern "C" {
#include "../../bridge.h"
}

#include <cstdio>
#include <cstdlib>
#include <cstring>

using Microsoft::WRL::ComPtr;

enum EnvState { EnvNone, EnvPending, EnvReady, EnvFailed };

static ComPtr<ICoreWebView2Environment> s_env;
static EnvState s_envState = EnvNone;
static int      s_pointerTarget = ION_WEBVIEW_INVALID;

WebView2State *ionWebView2At(int id) {
    IonWebviewSlot *slot = ion_webview_get(id);
    return slot ? static_cast<WebView2State *>(slot->platformState) : nullptr;
}

ICoreWebView2Environment *ionWebView2Env() { return s_env.Get(); }

class AddScriptCompletedCallback final
    : public ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler {
public:
    AddScriptCompletedCallback() : m_refs(1) {}

    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **ppv) override {
        if (!ppv) return E_POINTER;
        if (IsEqualIID(riid, IID_IUnknown) ||
            IsEqualIID(riid, IID_ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler)) {
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
    HRESULT STDMETHODCALLTYPE Invoke(HRESULT hr, LPCWSTR scriptId) override {
        (void)hr; (void)scriptId;
        return S_OK;
    }

private:
    LONG m_refs;
};

static void applyBackground(WebView2State *st) {
    ComPtr<ICoreWebView2Controller2> c2;
    if (FAILED(st->controller->QueryInterface(IID_ICoreWebView2Controller2, (void **)&c2))) return;
    COREWEBVIEW2_COLOR color = { (BYTE)(st->transparent ? 0 : 255), 255, 255, 255 };
    c2->put_DefaultBackgroundColor(color);
}

static void destroyState(WebView2State *st) {
    if (st->webview) {
        st->webview->remove_WebMessageReceived(st->messageToken);
        st->webview->remove_NavigationStarting(st->navStartingToken);
        st->webview->remove_WebResourceRequested(st->resourceRequestedToken);
    }
    if (st->composition) {
        st->composition->remove_CursorChanged(st->cursorChangedToken);
        st->composition->put_RootVisualTarget(nullptr);
    }
    if (st->controller) st->controller->Close();
    if (st->visual) st->visual->Release();
    free(st->pendingUrl);
    delete st;
}

class CursorChangedCallback final : public ICoreWebView2CursorChangedEventHandler {
public:
    explicit CursorChangedCallback(int id) : m_refs(1), m_id(id) {}

    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **ppv) override {
        if (!ppv) return E_POINTER;
        if (IsEqualIID(riid, IID_IUnknown) ||
            IsEqualIID(riid, IID_ICoreWebView2CursorChangedEventHandler)) {
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
    HRESULT STDMETHODCALLTYPE Invoke(ICoreWebView2CompositionController *sender, IUnknown *args) override {
        (void)args;
        WebView2State *st = ionWebView2At(m_id);
        if (st == nullptr) return S_OK;
        HCURSOR cursor = nullptr;
        if (SUCCEEDED(sender->get_Cursor(&cursor))) st->cursor = cursor;
        if (s_pointerTarget == m_id) SetCursor(st->cursor);
        return S_OK;
    }

private:
    LONG m_refs;
    int  m_id;
};

static void settleDevTools(ICoreWebView2 *webview) {
    ComPtr<ICoreWebView2Settings> settings;
    if (FAILED(webview->get_Settings(&settings)) || !settings) return;
    const char *envDev = getenv("ION_DEVTOOLS");
    BOOL devtools = envDev != nullptr && (envDev[0] == '1' || _stricmp(envDev, "true") == 0 ||
                                          _stricmp(envDev, "yes") == 0 || _stricmp(envDev, "on") == 0);
    settings->put_AreDevToolsEnabled(devtools);
}

static void injectBootstrap(ICoreWebView2 *webview) {
    char *jsUtf8 = ion_build_bootstrap_js(ion_invoke_key(), "window.chrome.webview.postMessage(envelope);");
    if (jsUtf8 == nullptr) return;
    wchar_t *jsW = ionUtf8ToWide(jsUtf8);
    if (jsW != nullptr) {
        auto *addCb = new AddScriptCompletedCallback();
        webview->AddScriptToExecuteOnDocumentCreated(jsW, addCb);
        addCb->Release();
        free(jsW);
    }
    free(jsUtf8);
}

class ControllerCreatedCallback final
    : public ICoreWebView2CreateCoreWebView2CompositionControllerCompletedHandler {
public:
    explicit ControllerCreatedCallback(WebView2State *st) : m_refs(1), m_st(st) {}

    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **ppv) override {
        if (!ppv) return E_POINTER;
        if (IsEqualIID(riid, IID_IUnknown) ||
            IsEqualIID(riid, IID_ICoreWebView2CreateCoreWebView2CompositionControllerCompletedHandler)) {
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

    HRESULT STDMETHODCALLTYPE Invoke(HRESULT hr, ICoreWebView2CompositionController *composition) override {
        WebView2State *st = m_st;
        if (FAILED(hr) || composition == nullptr) {
            fprintf(stderr, "[ion] webview %d: composition controller create failed: 0x%08lx\n", st->id, (long)hr);
            if (st->released) destroyState(st);
            return hr;
        }
        st->composition = composition;
        if (FAILED(composition->QueryInterface(IID_ICoreWebView2Controller, (void **)&st->controller)) ||
            FAILED(st->controller->get_CoreWebView2(&st->webview)) || !st->webview) {
            fprintf(stderr, "[ion] webview %d: controller has no ICoreWebView2\n", st->id);
            if (st->released) destroyState(st);
            return E_FAIL;
        }
        if (st->released) {
            destroyState(st);
            return S_OK;
        }
        hr = composition->put_RootVisualTarget(st->visual);
        if (FAILED(hr)) {
            fprintf(stderr, "[ion] webview %d: put_RootVisualTarget failed: 0x%08lx\n", st->id, (long)hr);
            return hr;
        }
        ionCompCommit();
        auto *cursorCb = new CursorChangedCallback(st->id);
        composition->add_CursorChanged(cursorCb, &st->cursorChangedToken);
        cursorCb->Release();

        settleDevTools(st->webview.Get());
        st->controller->put_Bounds(st->bounds);
        st->controller->put_IsVisible(st->visible ? TRUE : FALSE);
        applyBackground(st);
        injectBootstrap(st->webview.Get());
        ionAttachMessageHandler(st->webview.Get(), st->id, &st->messageToken);
        ionAttachNavHandler(st->webview.Get(), &st->navStartingToken);
        ionAttachResourceHandler(st->webview.Get(), &st->resourceRequestedToken);

        if (st->pendingUrl != nullptr) {
            wchar_t *wurl = ionUtf8ToWide(st->pendingUrl);
            if (wurl != nullptr) {
                st->webview->Navigate(wurl);
                free(wurl);
            }
            free(st->pendingUrl);
            st->pendingUrl = nullptr;
        }
        return S_OK;
    }

private:
    LONG           m_refs;
    WebView2State *m_st;
};

static void requestController(WebView2State *st) {
    if (st->requested || st->released) return;
    ComPtr<ICoreWebView2Environment3> env3;
    if (FAILED(s_env->QueryInterface(IID_ICoreWebView2Environment3, (void **)&env3))) {
        fprintf(stderr, "[ion] WebView2 Runtime lacks ICoreWebView2Environment3 "
                        "(composition hosting) - update the WebView2 Runtime\n");
        return;
    }
    st->requested = true;
    auto *cb = new ControllerCreatedCallback(st);
    HRESULT hr = env3->CreateCoreWebView2CompositionController(st->hwnd, cb);
    cb->Release();
    if (FAILED(hr)) {
        st->requested = false;
        fprintf(stderr, "[ion] webview %d: CreateCoreWebView2CompositionController failed: 0x%08lx\n", st->id, (long)hr);
    }
}

class EnvCreatedCallback final
    : public ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler {
public:
    EnvCreatedCallback() : m_refs(1) {}

    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **ppv) override {
        if (!ppv) return E_POINTER;
        if (IsEqualIID(riid, IID_IUnknown) ||
            IsEqualIID(riid, IID_ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler)) {
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

    HRESULT STDMETHODCALLTYPE Invoke(HRESULT hr, ICoreWebView2Environment *env) override {
        if (FAILED(hr) || env == nullptr) {
            fprintf(stderr,
                "[ion] WebView2 environment create failed: 0x%08lx — is WebView2 Runtime installed?\n",
                (long)hr);
            s_envState = EnvFailed;
            return hr;
        }
        s_env = env;
        s_envState = EnvReady;
        for (int id = ion_webview_next(ION_WEBVIEW_INVALID); id != ION_WEBVIEW_INVALID; id = ion_webview_next(id)) {
            WebView2State *st = ionWebView2At(id);
            if (st != nullptr) requestController(st);
        }
        return S_OK;
    }

private:
    LONG m_refs;
};

// WebView2Loader.dll ships next to the .exe (vendored at vendor/webview2/
// runtime/x64/, copied in by the build/packaging step). We load it
// dynamically rather than link the MSVC .lib at build time because zig's
// MinGW toolchain can't natively consume MSVC COFF .lib files.

typedef HRESULT (STDAPICALLTYPE *PFN_CreateCoreWebView2EnvironmentWithOptions)(
    PCWSTR browserExecutableFolder,
    PCWSTR userDataFolder,
    ICoreWebView2EnvironmentOptions *environmentOptions,
    ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler *environmentCreatedHandler);

static PFN_CreateCoreWebView2EnvironmentWithOptions resolveCreateEnv() {
    static HMODULE s_loaderDll = nullptr;
    static PFN_CreateCoreWebView2EnvironmentWithOptions s_fn = nullptr;
    if (s_fn != nullptr) return s_fn;

    s_loaderDll = LoadLibraryW(L"WebView2Loader.dll");
    if (s_loaderDll == nullptr) {
        fprintf(stderr, "[ion] LoadLibrary(WebView2Loader.dll) failed — "
                        "ensure the DLL ships next to the executable\n");
        return nullptr;
    }
    s_fn = (PFN_CreateCoreWebView2EnvironmentWithOptions)
        GetProcAddress(s_loaderDll, "CreateCoreWebView2EnvironmentWithOptions");
    if (s_fn == nullptr) {
        fprintf(stderr, "[ion] GetProcAddress(CreateCoreWebView2EnvironmentWithOptions) failed\n");
    }
    return s_fn;
}

// User-data folder defaults to `<exe-dir>\<exe>.WebView2\` which is unwritable
// when the app is installed under Program Files. Compute a per-app folder
// under %LOCALAPPDATA% so installed apps work without admin elevation.
static void buildUserDataPath(wchar_t *out, size_t outCap) {
    wchar_t appdata[MAX_PATH];
    DWORD n = GetEnvironmentVariableW(L"LOCALAPPDATA", appdata, MAX_PATH);
    if (n == 0 || n >= MAX_PATH) {
        out[0] = L'\0';
        return;
    }
    wchar_t exePath[MAX_PATH];
    DWORD m = GetModuleFileNameW(NULL, exePath, MAX_PATH);
    if (m == 0 || m >= MAX_PATH) { out[0] = L'\0'; return; }
    wchar_t *sep = wcsrchr(exePath, L'\\');
    wchar_t *baseStart = sep ? sep + 1 : exePath;
    wchar_t *dot = wcsrchr(baseStart, L'.');
    if (dot) *dot = L'\0';
    _snwprintf_s(out, outCap, _TRUNCATE, L"%ls\\ion-%ls", appdata, baseStart);
}

static int startEnvironment(void) {
    if (s_envState == EnvPending || s_envState == EnvReady) return 1;
    auto createEnv = resolveCreateEnv();
    if (createEnv == nullptr) return 0;
    ionProtoFreeze();
    wchar_t userDataPath[MAX_PATH];
    buildUserDataPath(userDataPath, MAX_PATH);
    ICoreWebView2EnvironmentOptions *options = ionBuildEnvOptions();
    auto *cb = new EnvCreatedCallback();
    s_envState = EnvPending;
    HRESULT hr = createEnv(nullptr, userDataPath[0] != L'\0' ? userDataPath : nullptr, options, cb);
    cb->Release();
    if (options) options->Release();
    if (FAILED(hr)) {
        fprintf(stderr, "[ion] CreateCoreWebView2EnvironmentWithOptions request failed: 0x%08lx\n", (long)hr);
        s_envState = EnvFailed;
        return 0;
    }
    return 1;
}

extern "C" IonWebviewId ionWebviewCreate(IonWindowId win, const char *label, const char *url) {
    HWND hwnd = ionWinHwnd(win);
    auto *device = static_cast<IDCompositionDevice *>(ionCompDevice());
    if (hwnd == nullptr || device == nullptr) {
        fprintf(stderr, "[ion] ionWebviewCreate: window %d does not exist\n", (int)win);
        return ION_WEBVIEW_INVALID;
    }
    if (s_envState == EnvFailed || !startEnvironment()) return ION_WEBVIEW_INVALID;
    int id = ion_webview_alloc(label, win);
    if (id == ION_WEBVIEW_INVALID) {
        fprintf(stderr, "[ion] ionWebviewCreate: label '%s' is empty, taken or too long, or the table is full\n",
                label ? label : "");
        return ION_WEBVIEW_INVALID;
    }
    auto *st = new WebView2State();
    st->id = id;
    st->window = win;
    st->hwnd = hwnd;
    if (FAILED(device->CreateVisual(&st->visual))) {
        fprintf(stderr, "[ion] ionWebviewCreate: CreateVisual failed\n");
        ion_webview_free(id);
        delete st;
        return ION_WEBVIEW_INVALID;
    }
    if (url != nullptr && url[0] != '\0') st->pendingUrl = strdup(url);
    ion_webview_get(id)->platformState = st;
    if (s_envState == EnvReady) requestController(st);
    return id;
}

extern "C" void ionWebviewRelease(IonWebviewId id) {
    WebView2State *st = ionWebView2At(id);
    if (st == nullptr) return;
    ion_webview_free(id);
    if (s_pointerTarget == id) s_pointerTarget = ION_WEBVIEW_INVALID;
    if (st->requested && !st->controller) {
        st->released = true;
        return;
    }
    destroyState(st);
    ionCompCommit();
}

void ionWebView2CloseWindow(IonWindowId win) {
    for (int id = ion_webview_next(ION_WEBVIEW_INVALID); id != ION_WEBVIEW_INVALID; id = ion_webview_next(id)) {
        IonWebviewSlot *slot = ion_webview_get(id);
        if (slot != nullptr && slot->window == win) ionWebviewRelease(id);
    }
}

void ionWebView2ParentMoved(IonWindowId win) {
    for (int id = ion_webview_next(ION_WEBVIEW_INVALID); id != ION_WEBVIEW_INVALID; id = ion_webview_next(id)) {
        WebView2State *st = ionWebView2At(id);
        if (st != nullptr && st->window == win && st->controller) st->controller->NotifyParentWindowPositionChanged();
    }
}

extern "C" void *ionWebviewNode(IonWebviewId id) {
    WebView2State *st = ionWebView2At(id);
    return st ? st->visual : nullptr;
}

extern "C" void ionWebviewSetBounds(IonWebviewId id, int x, int y, int w, int h) {
    WebView2State *st = ionWebView2At(id);
    if (st == nullptr) return;
    st->bounds = RECT{ (LONG)x, (LONG)y, (LONG)(x + (w > 0 ? w : 0)), (LONG)(y + (h > 0 ? h : 0)) };
    if (st->controller) st->controller->put_Bounds(st->bounds);
}

extern "C" void ionWebviewSetVisible(IonWebviewId id, int visible) {
    WebView2State *st = ionWebView2At(id);
    if (st == nullptr) return;
    st->visible = visible != 0;
    if (st->controller) st->controller->put_IsVisible(st->visible ? TRUE : FALSE);
}

extern "C" void ionWebviewSetTransparent(IonWebviewId id, int transparent) {
    WebView2State *st = ionWebView2At(id);
    if (st == nullptr) return;
    st->transparent = transparent != 0;
    if (st->controller) applyBackground(st);
}

extern "C" void ionWebviewNavigate(IonWebviewId id, const char *url) {
    WebView2State *st = ionWebView2At(id);
    if (st == nullptr || url == nullptr) return;
    if (!st->webview) {
        free(st->pendingUrl);
        st->pendingUrl = strdup(url);
        return;
    }
    wchar_t *wurl = ionUtf8ToWide(url);
    if (wurl == nullptr) return;
    st->webview->Navigate(wurl);
    free(wurl);
}

extern "C" void ionWebviewFocus(IonWebviewId id) {
    WebView2State *st = ionWebView2At(id);
    if (st == nullptr || !st->controller) return;
    ionWinKeyFlush();
    st->controller->MoveFocus(COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC);
}

static UINT mouseMessage(int kind, int button, DWORD *data) {
    *data = 0;
    switch (kind) {
        case ION_POINTER_MOVE:  return WM_MOUSEMOVE;
        case ION_POINTER_LEAVE: return WM_MOUSELEAVE;
        case ION_POINTER_WHEEL: return WM_MOUSEWHEEL;
        case ION_POINTER_HWHEEL: return WM_MOUSEHWHEEL;
        case ION_POINTER_DOWN:
        case ION_POINTER_UP: {
            int down = kind == ION_POINTER_DOWN;
            switch (button) {
                case 1: return down ? WM_LBUTTONDOWN : WM_LBUTTONUP;
                case 2: return down ? WM_RBUTTONDOWN : WM_RBUTTONUP;
                case 3: return down ? WM_MBUTTONDOWN : WM_MBUTTONUP;
                case 4: *data = XBUTTON1; return down ? WM_XBUTTONDOWN : WM_XBUTTONUP;
                case 5: *data = XBUTTON2; return down ? WM_XBUTTONDOWN : WM_XBUTTONUP;
                default: return 0;
            }
        }
        default: return 0;
    }
}

static COREWEBVIEW2_MOUSE_EVENT_VIRTUAL_KEYS heldKeys(void) {
    int keys = 0;
    if (GetKeyState(VK_LBUTTON) & 0x8000)  keys |= MK_LBUTTON;
    if (GetKeyState(VK_RBUTTON) & 0x8000)  keys |= MK_RBUTTON;
    if (GetKeyState(VK_MBUTTON) & 0x8000)  keys |= MK_MBUTTON;
    if (GetKeyState(VK_XBUTTON1) & 0x8000) keys |= MK_XBUTTON1;
    if (GetKeyState(VK_XBUTTON2) & 0x8000) keys |= MK_XBUTTON2;
    if (GetKeyState(VK_SHIFT) & 0x8000)    keys |= MK_SHIFT;
    if (GetKeyState(VK_CONTROL) & 0x8000)  keys |= MK_CONTROL;
    return (COREWEBVIEW2_MOUSE_EVENT_VIRTUAL_KEYS)keys;
}

extern "C" void ionWebviewForwardPointer(IonWebviewId id, int kind, double x, double y, int button, double delta) {
    WebView2State *st = ionWebView2At(id);
    if (st == nullptr || !st->composition) return;
    DWORD data = 0;
    UINT msg = mouseMessage(kind, button, &data);
    if (msg == 0) {
        fprintf(stderr, "[ion] ionWebviewForwardPointer: unknown kind %d / button %d\n", kind, button);
        return;
    }
    if (kind == ION_POINTER_WHEEL || kind == ION_POINTER_HWHEEL) data = (DWORD)(LONG)(delta * WHEEL_DELTA);
    POINT pt = { (LONG)x, (LONG)y };
    st->composition->SendMouseInput((COREWEBVIEW2_MOUSE_EVENT_KIND)msg, heldKeys(), data, pt);
    if (kind == ION_POINTER_LEAVE) {
        if (s_pointerTarget == id) s_pointerTarget = ION_WEBVIEW_INVALID;
    } else {
        s_pointerTarget = id;
    }
}

int ionWebView2LastPointerTarget(void) { return s_pointerTarget; }

HCURSOR ionWebView2Cursor(int id) {
    WebView2State *st = ionWebView2At(id);
    return st ? st->cursor : nullptr;
}
