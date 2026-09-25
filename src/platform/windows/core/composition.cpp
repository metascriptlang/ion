#include "../state.h"
#include "../internal.h"
extern "C" {
#include "../../bridge.h"
}
#include "../../common/inputEvents.h"

#include <dcomp.h>
#include <dxgi1_2.h>
#include <cstdio>
#include <cstring>

#define ION_MAX_SURFACES 16

struct IonWinSurface {
    int                  used;
    int                  z;
    int                  visible;
    int                  inputMode;
    RECT                 inputRect;
    RECT                 imeRect;
    IDCompositionVisual *visual;
    IDXGISwapChain1     *swapChain;
    HWND                 adopted;
};

static IDCompositionDevice *s_device  = nullptr;
static IDCompositionTarget *s_target  = nullptr;
static IDCompositionVisual *s_root    = nullptr;
static IDCompositionVisual *s_webview = nullptr;
static IonWinSurface        s_surfaces[ION_MAX_SURFACES];
static int                  s_focused = ION_RENDER_SURFACE_INVALID;
static int                  s_clientW = 0, s_clientH = 0;
static int                  s_frameSet = 0;
static RECT                 s_frame = { 0, 0, 0, 0 };
static int                  s_webviewVisible = 1;
static IonInputSink         s_sink = nullptr;

static IonWinSurface *surfaceAt(IonRenderSurfaceId id) {
    if (id < 0 || id >= ION_MAX_SURFACES || !s_surfaces[id].used) return nullptr;
    return &s_surfaces[id];
}

static double currentScale(void) {
    HWND hwnd = ionGetMainHwnd();
    UINT dpi = hwnd ? GetDpiForWindow(hwnd) : 96;
    return (double)(dpi ? dpi : 96) / 96.0;
}

static void commit(void) {
    if (s_device) s_device->Commit();
}

static void pushResize(int id) {
    IonInputRecord r;
    memset(&r, 0, sizeof r);
    r.type = ION_INPUT_RESIZE;
    r.surface = id;
    r.x = currentScale();
    r.p1 = s_clientW;
    r.p2 = s_clientH;
    ion_input_push_record(&r);
}

static void pushFocus(int id, int gained) {
    IonInputRecord r;
    memset(&r, 0, sizeof r);
    r.type = ION_INPUT_FOCUS;
    r.surface = id;
    r.p1 = gained;
    ion_input_push_record(&r);
}

static int belowCount(void) {
    int n = 0;
    for (int i = 0; i < ION_MAX_SURFACES; i++)
        if (s_surfaces[i].used && s_surfaces[i].z == ION_SURFACE_BELOW) n++;
    return n;
}

static void applyWebviewFrame(void) {
    RECT f = s_frameSet ? s_frame : RECT{ 0, 0, s_clientW, s_clientH };
    if (s_webview) {
        s_webview->SetOffsetX((float)f.left);
        s_webview->SetOffsetY((float)f.top);
        commit();
    }
    ionWebView2SetBounds(f.left, f.top, f.right - f.left, f.bottom - f.top);
}

extern "C" int ionCompInit(HWND hwnd) {
    memset(s_surfaces, 0, sizeof s_surfaces);
    HRESULT hr = DCompositionCreateDevice2(nullptr, __uuidof(IDCompositionDevice), (void **)&s_device);
    if (FAILED(hr)) {
        fprintf(stderr, "[ion] DCompositionCreateDevice2 failed: 0x%08lx\n", (long)hr);
        return 0;
    }
    hr = s_device->CreateTargetForHwnd(hwnd, TRUE, &s_target);
    if (SUCCEEDED(hr)) hr = s_device->CreateVisual(&s_root);
    if (SUCCEEDED(hr)) hr = s_target->SetRoot(s_root);
    if (SUCCEEDED(hr)) hr = s_device->CreateVisual(&s_webview);
    if (SUCCEEDED(hr)) hr = s_root->AddVisual(s_webview, TRUE, nullptr);
    if (FAILED(hr)) {
        fprintf(stderr, "[ion] DirectComposition tree setup failed: 0x%08lx\n", (long)hr);
        return 0;
    }
    RECT rc;
    GetClientRect(hwnd, &rc);
    s_clientW = rc.right - rc.left;
    s_clientH = rc.bottom - rc.top;
    commit();
    return 1;
}

static void releaseSurface(IonWinSurface *s) {
    if (s->visual) {
        if (s_root) s_root->RemoveVisual(s->visual);
        s->visual->Release();
    }
    if (s->swapChain) s->swapChain->Release();
    if (s->adopted) {
        ShowWindow(s->adopted, SW_HIDE);
        SetParent(s->adopted, nullptr);
    }
    memset(s, 0, sizeof *s);
}

extern "C" void ionCompShutdown(void) {
    for (int i = 0; i < ION_MAX_SURFACES; i++)
        if (s_surfaces[i].used) releaseSurface(&s_surfaces[i]);
    if (s_webview) { s_webview->Release(); s_webview = nullptr; }
    if (s_root)    { s_root->Release();    s_root = nullptr; }
    if (s_target)  { s_target->Release();  s_target = nullptr; }
    if (s_device)  { s_device->Release();  s_device = nullptr; }
    s_focused = ION_RENDER_SURFACE_INVALID;
    s_frameSet = 0;
    s_webviewVisible = 1;
}

extern "C" void *ionCompWebviewVisual(void) { return s_webview; }

extern "C" void ionCompCommit(void) { commit(); }

extern "C" void ionCompClientResized(int w, int h) {
    s_clientW = w;
    s_clientH = h;
    if (!s_frameSet) applyWebviewFrame();
    for (int i = 0; i < ION_MAX_SURFACES; i++) {
        IonWinSurface *s = &s_surfaces[i];
        if (!s->used) continue;
        if (s->adopted) MoveWindow(s->adopted, 0, 0, w, h, TRUE);
        pushResize(i);
    }
}

extern "C" void ionCompDpiChanged(void) {
    for (int i = 0; i < ION_MAX_SURFACES; i++)
        if (s_surfaces[i].used) pushResize(i);
}

static int regionClaims(const IonWinSurface *s, int x, int y) {
    if (!s->visible) return 0;
    if (s->inputMode == ION_INPUT_FULL) return 1;
    if (s->inputMode == ION_INPUT_RECT) {
        POINT p = { x, y };
        return PtInRect(&s->inputRect, p);
    }
    return 0;
}

extern "C" int ionCompRoute(int x, int y) {
    for (int i = ION_MAX_SURFACES - 1; i >= 0; i--)
        if (s_surfaces[i].used && s_surfaces[i].z == ION_SURFACE_ABOVE && regionClaims(&s_surfaces[i], x, y))
            return i;
    if (s_webviewVisible) {
        RECT f = s_frameSet ? s_frame : RECT{ 0, 0, s_clientW, s_clientH };
        POINT p = { x, y };
        if (PtInRect(&f, p)) return ION_COMP_ROUTE_WEBVIEW;
    }
    for (int i = ION_MAX_SURFACES - 1; i >= 0; i--)
        if (s_surfaces[i].used && s_surfaces[i].z == ION_SURFACE_BELOW && regionClaims(&s_surfaces[i], x, y))
            return i;
    return ION_COMP_ROUTE_NONE;
}

extern "C" void ionCompWebviewOrigin(int *x, int *y) {
    *x = s_frameSet ? s_frame.left : 0;
    *y = s_frameSet ? s_frame.top : 0;
}

extern "C" void ionCompPointer(int surf, int type, int px, int py, double p1, double p2) {
    double w = s_clientW > 0 ? (double)s_clientW : 1.0;
    double h = s_clientH > 0 ? (double)s_clientH : 1.0;
    double fx = px / w, fy = py / h;
    if (type == ION_INPUT_MOTION) { p1 /= w; p2 /= h; }
    if (s_sink) { s_sink(type, fx, fy, p1, p2); return; }
    IonInputRecord r;
    memset(&r, 0, sizeof r);
    r.type = type;
    r.surface = surf;
    r.x = fx;
    r.y = fy;
    r.p1 = p1;
    r.p2 = p2;
    ion_input_push_record(&r);
}

extern "C" int ionCompFocusedSurface(void) { return s_focused; }

extern "C" void ionCompFocusSurface(int surf, int hostHasFocus) {
    if (surf == s_focused) return;
    if (s_focused != ION_RENDER_SURFACE_INVALID && hostHasFocus) pushFocus(s_focused, 0);
    s_focused = surf;
    if (s_focused != ION_RENDER_SURFACE_INVALID && hostHasFocus) pushFocus(s_focused, 1);
}

extern "C" void ionCompHostFocus(int gained) {
    if (s_focused != ION_RENDER_SURFACE_INVALID) pushFocus(s_focused, gained);
}

extern "C" int ionCompImeRect(int surf, RECT *out) {
    IonWinSurface *s = surfaceAt(surf);
    if (s == nullptr) return 0;
    *out = s->imeRect;
    return 1;
}

// ---- bridge.h render surface --------------------------------------------

extern "C" IonRenderSurfaceId ionRenderSurfaceCreate(IonWindowId win, int z) {
    if (win != 0 || ionGetMainHwnd() == nullptr || s_device == nullptr) return ION_RENDER_SURFACE_INVALID;
    if (z != ION_SURFACE_BELOW && z != ION_SURFACE_ABOVE) return ION_RENDER_SURFACE_INVALID;
    for (int i = 0; i < ION_MAX_SURFACES; i++) {
        IonWinSurface *s = &s_surfaces[i];
        if (s->used) continue;
        if (FAILED(s_device->CreateVisual(&s->visual))) return ION_RENDER_SURFACE_INVALID;
        HRESULT hr = z == ION_SURFACE_BELOW
            ? s_root->AddVisual(s->visual, FALSE, s_webview)
            : s_root->AddVisual(s->visual, TRUE, nullptr);
        if (FAILED(hr)) {
            s->visual->Release();
            s->visual = nullptr;
            return ION_RENDER_SURFACE_INVALID;
        }
        s->used = 1;
        s->z = z;
        s->visible = 1;
        s->inputMode = ION_INPUT_FULL;
        commit();
        if (z == ION_SURFACE_BELOW && belowCount() == 1) ionWebView2SetTransparent(1);
        if (s_focused == ION_RENDER_SURFACE_INVALID) ionCompFocusSurface(i, GetFocus() == ionGetMainHwnd());
        pushResize(i);
        return i;
    }
    return ION_RENDER_SURFACE_INVALID;
}

extern "C" void ionRenderSurfaceAdopt(IonRenderSurfaceId surf, void *nativeView) {
    IonWinSurface *s = surfaceAt(surf);
    HWND child = (HWND)nativeView;
    if (s == nullptr || child == nullptr || !IsWindow(child)) return;
    LONG_PTR style = GetWindowLongPtrW(child, GWL_STYLE);
    SetWindowLongPtrW(child, GWL_STYLE, (style & ~(WS_POPUP | WS_CAPTION | WS_THICKFRAME)) | WS_CHILD);
    SetParent(child, ionGetMainHwnd());
    MoveWindow(child, 0, 0, s_clientW, s_clientH, TRUE);
    ShowWindow(child, s->visible ? SW_SHOW : SW_HIDE);
    s->adopted = child;
}

extern "C" void ionRenderSurfaceAdoptLayer(IonRenderSurfaceId surf, long long caLayer) {
    (void)surf; (void)caLayer;
}

extern "C" void *ionRenderSurfaceLayer(IonRenderSurfaceId surf) {
    (void)surf;
    return nullptr;
}

extern "C" int ionRenderSurfaceAttachSwapChain(IonRenderSurfaceId surf, long long dxgiSwapChain1) {
    IonWinSurface *s = surfaceAt(surf);
    if (s == nullptr || dxgiSwapChain1 == 0) return 0;
    IUnknown *unk = (IUnknown *)(intptr_t)dxgiSwapChain1;
    IDXGISwapChain1 *sc = nullptr;
    if (FAILED(unk->QueryInterface(__uuidof(IDXGISwapChain1), (void **)&sc))) {
        fprintf(stderr, "[ion] ionRenderSurfaceAttachSwapChain: not an IDXGISwapChain1\n");
        return 0;
    }
    HRESULT hr = s->visual->SetContent(sc);
    if (FAILED(hr)) {
        fprintf(stderr, "[ion] ionRenderSurfaceAttachSwapChain: SetContent failed 0x%08lx "
                        "(was it created with CreateSwapChainForComposition?)\n", (long)hr);
        sc->Release();
        return 0;
    }
    if (s->swapChain) s->swapChain->Release();
    s->swapChain = sc;
    commit();
    return 1;
}

extern "C" void ionRenderSurfaceSetImeRect(IonRenderSurfaceId surf, int x, int y, int w, int h) {
    IonWinSurface *s = surfaceAt(surf);
    if (s == nullptr) return;
    s->imeRect = RECT{ x, y, x + w, y + h };
    if (surf == s_focused) ionWinImeReposition();
}

extern "C" void ionRenderSurfaceSetInputSink(IonInputSink sink) { s_sink = sink; }

extern "C" void ionRenderSurfaceSetVisible(IonRenderSurfaceId surf, int visible) {
    IonWinSurface *s = surfaceAt(surf);
    if (s == nullptr) return;
    s->visible = visible ? 1 : 0;
    if (s->visual) s->visual->SetContent(s->visible ? s->swapChain : nullptr);
    if (s->adopted) ShowWindow(s->adopted, s->visible ? SW_SHOW : SW_HIDE);
    commit();
}

extern "C" void ionRenderSurfaceSyncFrame(IonRenderSurfaceId surf) {
    IonWinSurface *s = surfaceAt(surf);
    if (s == nullptr) return;
    if (s->adopted) MoveWindow(s->adopted, 0, 0, s_clientW, s_clientH, TRUE);
    pushResize(surf);
}

extern "C" void ionRenderSurfaceSetInputRegion(IonRenderSurfaceId surf, int mode, int x, int y, int w, int h) {
    IonWinSurface *s = surfaceAt(surf);
    if (s == nullptr) return;
    s->inputMode = mode;
    s->inputRect = RECT{ x, y, x + w, y + h };
}

extern "C" void ionRenderSurfaceRelease(IonRenderSurfaceId surf) {
    IonWinSurface *s = surfaceAt(surf);
    if (s == nullptr) return;
    int wasBelow = s->z == ION_SURFACE_BELOW;
    if (surf == s_focused) ionCompFocusSurface(ION_RENDER_SURFACE_INVALID, GetFocus() == ionGetMainHwnd());
    releaseSurface(s);
    commit();
    if (wasBelow && belowCount() == 0) ionWebView2SetTransparent(0);
}

// ---- bridge.h webview as element -----------------------------------------

extern "C" void ionWebviewSetFrame(IonWindowId win, int x, int y, int w, int h) {
    if (win != 0) return;
    s_frameSet = 1;
    s_frame = RECT{ x, y, x + (w > 0 ? w : 0), y + (h > 0 ? h : 0) };
    applyWebviewFrame();
}

extern "C" void ionWebviewSetVisible(IonWindowId win, int visible) {
    if (win != 0) return;
    s_webviewVisible = visible ? 1 : 0;
    ionWebView2SetVisible(s_webviewVisible);
}
