// Ion Windows — WebView2 controller lifecycle.
//
// Async init chain (each step kicks off the next via a callback):
//   1. ionWebView2Start: LoadLibraryW("WebView2Loader.dll") → GetProcAddress
//      for CreateCoreWebView2EnvironmentWithOptions → call it with
//      EnvCreatedCallback as the completion handler. Returns synchronously.
//   2. EnvCreatedCallback::Invoke: got env → Environment3's
//      CreateCoreWebView2CompositionController with ControllerCreatedCallback.
//   3. ControllerCreatedCallback::Invoke: got controller → cache controller
//      + webview → hang it on the composition tree's webview visual → apply
//      the pending frame → inject bootstrap script → attach event handlers
//      (WebMessageReceived from messaging.cpp + NavigationStarting from
//      nav.cpp) → Navigate(url).
//
// Each callback class is a hand-rolled IUnknown impl (zig's bundled MinGW
// ships wrl/client.h for ComPtr but NOT wrl/event.h for Callback<>).

#include "internal.hpp"
#include "../utf8.h"
#include "../internal.h"
#include "../../common/invokekey.h"
#include "../../common/bootstrap.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>

using Microsoft::WRL::ComPtr;

// ---- AddScriptCompletedCallback -------------------------------------------
// Required by AddScriptToExecuteOnDocumentCreated; we don't care about the
// returned script ID, so this is a no-op handler.

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

static RECT s_bounds      = { 0, 0, 0, 0 };
static int  s_visible     = 1;
static int  s_transparent = 0;

static void applyBackground(WebView2State *st) {
    ComPtr<ICoreWebView2Controller2> c2;
    if (FAILED(st->controller->QueryInterface(IID_ICoreWebView2Controller2, (void **)&c2))) return;
    COREWEBVIEW2_COLOR color = { (BYTE)(s_transparent ? 0 : 255), 255, 255, 255 };
    c2->put_DefaultBackgroundColor(color);
}

class CursorChangedCallback final : public ICoreWebView2CursorChangedEventHandler {
public:
    CursorChangedCallback() : m_refs(1) {}

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
        WebView2State *st = ionGetWebView2State();
        if (st == nullptr) return S_OK;
        HCURSOR cursor = nullptr;
        if (SUCCEEDED(sender->get_Cursor(&cursor))) st->cursor = cursor;
        SetCursor(st->cursor);
        return S_OK;
    }

private:
    LONG m_refs;
};

// ---- ControllerCreatedCallback --------------------------------------------
// Step 3 of the init chain: controller is ready, finish wiring everything.

class ControllerCreatedCallback final
    : public ICoreWebView2CreateCoreWebView2CompositionControllerCompletedHandler {
public:
    ControllerCreatedCallback(HWND hwnd) : m_refs(1), m_hwnd(hwnd) {}

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
        if (FAILED(hr) || composition == nullptr) {
            fprintf(stderr, "[ion] WebView2 composition controller create failed: 0x%08lx\n", (long)hr);
            return hr;
        }

        WebView2State *st = ionGetWebView2State();
        if (st == nullptr) return E_UNEXPECTED;

        st->composition = composition;
        ComPtr<ICoreWebView2Controller> controller;
        if (FAILED(composition->QueryInterface(IID_ICoreWebView2Controller, (void **)&controller))) {
            fprintf(stderr, "[ion] composition controller has no ICoreWebView2Controller\n");
            return E_FAIL;
        }
        st->controller = controller;

        hr = composition->put_RootVisualTarget((IUnknown *)ionCompWebviewVisual());
        if (FAILED(hr)) {
            fprintf(stderr, "[ion] WebView2 put_RootVisualTarget failed: 0x%08lx\n", (long)hr);
            return hr;
        }
        ionCompCommit();
        auto *cursorCb = new CursorChangedCallback();
        composition->add_CursorChanged(cursorCb, &st->cursorChangedToken);
        cursorCb->Release();
        ComPtr<ICoreWebView2> webview;
        if (FAILED(controller->get_CoreWebView2(&webview)) || !webview) {
            fprintf(stderr, "[ion] get_CoreWebView2 failed\n");
            return E_FAIL;
        }
        st->webview = webview;

        // DevTools env-gate: off by default, on when ION_DEVTOOLS is set to a
        // truthy value. Mirrors macOS WKPreferences `developerExtrasEnabled`
        // logic in webview/bootstrap.m. WebView2's default is ON; we must
        // explicitly disable for production safety.
        ComPtr<ICoreWebView2Settings> settings;
        if (SUCCEEDED(webview->get_Settings(&settings)) && settings) {
            const char *envDev = getenv("ION_DEVTOOLS");
            BOOL devtools = FALSE;
            if (envDev != nullptr && envDev[0] != '\0') {
                if (envDev[0] == '1' ||
                    _stricmp(envDev, "true") == 0 ||
                    _stricmp(envDev, "yes")  == 0 ||
                    _stricmp(envDev, "on")   == 0) {
                    devtools = TRUE;
                }
            }
            settings->put_AreDevToolsEnabled(devtools);
        }

        controller->put_Bounds(s_bounds);
        controller->put_IsVisible(s_visible ? TRUE : FALSE);
        applyBackground(st);

        // Inject the bootstrap script — shared template, Windows transport line.
        // The bootstrap itself includes a main-frame guard (see common/bootstrap.c)
        // since WebView2 has no `forMainFrameOnly` flag on AddScript injection.
        char *jsUtf8 = ion_build_bootstrap_js(
            ion_invoke_key(),
            "window.chrome.webview.postMessage(envelope);"
        );
        if (jsUtf8 != nullptr) {
            wchar_t *jsW = ionUtf8ToWide(jsUtf8);
            if (jsW != nullptr) {
                auto *addCb = new AddScriptCompletedCallback();
                webview->AddScriptToExecuteOnDocumentCreated(jsW, addCb);
                addCb->Release();
                free(jsW);
            }
            free(jsUtf8);
        }

        // Attach event handlers (defined in messaging.cpp + nav.cpp + protocol.cpp).
        ionAttachMessageHandler(webview.Get(), &st->messageToken);
        ionAttachNavHandler(webview.Get(), &st->navStartingToken);
        ionAttachResourceHandler(webview.Get(), &st->resourceRequestedToken);

        // Navigate to the deferred URL captured in ionWebView2Start.
        if (st->pendingUrl != nullptr) {
            wchar_t *wurl = ionUtf8ToWide(st->pendingUrl);
            if (wurl != nullptr) {
                webview->Navigate(wurl);
                free(wurl);
            }
            free(st->pendingUrl);
            st->pendingUrl = nullptr;
        }

        return S_OK;
    }

private:
    LONG m_refs;
    HWND m_hwnd;
};

// ---- EnvCreatedCallback ---------------------------------------------------
// Step 2 of the init chain: environment is ready, kick off controller create.

class EnvCreatedCallback final
    : public ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler {
public:
    EnvCreatedCallback(HWND hwnd) : m_refs(1), m_hwnd(hwnd) {}

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
            return hr;
        }

        // Stash env — custom-protocol handler calls env->CreateWebResourceResponse.
        WebView2State *st = ionGetWebView2State();
        if (st != nullptr) st->env = env;

        ComPtr<ICoreWebView2Environment3> env3;
        if (FAILED(env->QueryInterface(IID_ICoreWebView2Environment3, (void **)&env3))) {
            fprintf(stderr, "[ion] WebView2 Runtime lacks ICoreWebView2Environment3 "
                            "(composition hosting) - update the WebView2 Runtime\n");
            return E_NOINTERFACE;
        }
        auto *cb = new ControllerCreatedCallback(m_hwnd);
        HRESULT r = env3->CreateCoreWebView2CompositionController(m_hwnd, cb);
        cb->Release();
        return r;
    }

private:
    LONG m_refs;
    HWND m_hwnd;
};

// ---- Loader DLL resolution ------------------------------------------------
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
                        "ensure the DLL ships next to ion.exe\n");
        return nullptr;
    }
    s_fn = (PFN_CreateCoreWebView2EnvironmentWithOptions)
        GetProcAddress(s_loaderDll, "CreateCoreWebView2EnvironmentWithOptions");
    if (s_fn == nullptr) {
        fprintf(stderr, "[ion] GetProcAddress(CreateCoreWebView2EnvironmentWithOptions) failed\n");
    }
    return s_fn;
}

// ---- Public entry points (C-callable) -------------------------------------

// User-data folder defaults to `<exe-dir>\<exe>.WebView2\` which is unwritable
// when the app is installed under Program Files. Compute a per-app folder
// under %LOCALAPPDATA% so installed apps work without admin elevation.
static void buildUserDataPath(wchar_t *out, size_t outCap) {
    wchar_t appdata[MAX_PATH];
    DWORD n = GetEnvironmentVariableW(L"LOCALAPPDATA", appdata, MAX_PATH);
    if (n == 0 || n >= MAX_PATH) {
        out[0] = L'\0';  // signals "use WebView2 default" to the caller
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

extern "C" int ionWebView2Start(HWND hwnd, const char *url) {
    if (hwnd == nullptr) return 0;

    auto createEnv = resolveCreateEnv();
    if (createEnv == nullptr) return 0;

    // Allocate state up-front so the async callbacks have a place to land.
    auto *st = new WebView2State();
    if (url != nullptr && url[0] != '\0') {
        st->pendingUrl = strdup(url);
    }
    s_webview2State = st;

    wchar_t userDataPath[MAX_PATH];
    buildUserDataPath(userDataPath, MAX_PATH);

    // Env options carry the proto-registry's scheme list. WebView2 requires
    // custom schemes declared at env creation; can't add post-hoc.
    ICoreWebView2EnvironmentOptions *options = ionBuildEnvOptions();

    auto *cb = new EnvCreatedCallback(hwnd);
    HRESULT hr = createEnv(nullptr,
                           userDataPath[0] != L'\0' ? userDataPath : nullptr,
                           options, cb);
    cb->Release();
    if (options) options->Release();

    if (FAILED(hr)) {
        fprintf(stderr,
            "[ion] CreateCoreWebView2EnvironmentWithOptions request failed: 0x%08lx\n",
            (long)hr);
        free(st->pendingUrl);
        delete st;
        s_webview2State = nullptr;
        return 0;
    }
    return 1;
}

extern "C" void ionWebView2Shutdown(void) {
    WebView2State *st = ionGetWebView2State();
    if (st == nullptr) return;

    if (st->webview) {
        // Detach handlers before releasing — avoids dangling callback fires.
        st->webview->remove_WebMessageReceived(st->messageToken);
        st->webview->remove_NavigationStarting(st->navStartingToken);
        st->webview->remove_WebResourceRequested(st->resourceRequestedToken);
    }
    if (st->composition) {
        st->composition->remove_CursorChanged(st->cursorChangedToken);
        st->composition->put_RootVisualTarget(nullptr);
    }
    if (st->controller) {
        st->controller->Close();
    }
    free(st->pendingUrl);
    delete st;
    s_webview2State = nullptr;
}

extern "C" void ionWebView2SetBounds(int x, int y, int width, int height) {
    s_bounds = RECT{ (LONG)x, (LONG)y, (LONG)(x + width), (LONG)(y + height) };
    WebView2State *st = ionGetWebView2State();
    if (st == nullptr || !st->controller) return;
    st->controller->put_Bounds(s_bounds);
}

extern "C" void ionWebView2SetVisible(int visible) {
    s_visible = visible ? 1 : 0;
    WebView2State *st = ionGetWebView2State();
    if (st == nullptr || !st->controller) return;
    st->controller->put_IsVisible(s_visible ? TRUE : FALSE);
}

extern "C" void ionWebView2SetTransparent(int transparent) {
    s_transparent = transparent ? 1 : 0;
    WebView2State *st = ionGetWebView2State();
    if (st == nullptr || !st->controller) return;
    applyBackground(st);
}

extern "C" void ionWebView2Focus(void) {
    WebView2State *st = ionGetWebView2State();
    if (st == nullptr || !st->controller) return;
    st->controller->MoveFocus(COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC);
}

extern "C" void ionWebView2ParentMoved(void) {
    WebView2State *st = ionGetWebView2State();
    if (st == nullptr || !st->controller) return;
    st->controller->NotifyParentWindowPositionChanged();
}

extern "C" void ionWebView2SendMouse(UINT msg, WPARAM wParam, DWORD mouseData, int x, int y) {
    WebView2State *st = ionGetWebView2State();
    if (st == nullptr || !st->composition) return;
    POINT pt = { x, y };
    st->composition->SendMouseInput(
        (COREWEBVIEW2_MOUSE_EVENT_KIND)msg,
        (COREWEBVIEW2_MOUSE_EVENT_VIRTUAL_KEYS)GET_KEYSTATE_WPARAM(wParam),
        mouseData, pt);
}

extern "C" HCURSOR ionWebView2Cursor(void) {
    WebView2State *st = ionGetWebView2State();
    return st != nullptr ? st->cursor : nullptr;
}
