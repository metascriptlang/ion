#include "../state.h"
#include "../internal.h"
extern "C" {
#include "../../bridge.h"
}

#include <d3d11.h>
#include <d2d1_1.h>
#include <dcomp.h>
#include <dxgi1_2.h>
#include <cstdio>

static ID3D11Device        *s_d3d     = nullptr;
static ID2D1Factory1       *s_factory = nullptr;
static ID2D1Device         *s_d2d     = nullptr;
static IDCompositionDevice *s_device  = nullptr;
static int                  s_targets = 0;

template <class T> static void release(T *&p) {
    if (p) { p->Release(); p = nullptr; }
}

static HRESULT createD3D(D3D_DRIVER_TYPE driver) {
    const D3D_FEATURE_LEVEL levels[] = {
        D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0, D3D_FEATURE_LEVEL_10_1, D3D_FEATURE_LEVEL_10_0,
    };
    return D3D11CreateDevice(nullptr, driver, nullptr, D3D11_CREATE_DEVICE_BGRA_SUPPORT,
                             levels, ARRAYSIZE(levels), D3D11_SDK_VERSION, &s_d3d, nullptr, nullptr);
}

static HRESULT createDevices(void) {
    HRESULT hr = createD3D(D3D_DRIVER_TYPE_HARDWARE);
    if (FAILED(hr)) hr = createD3D(D3D_DRIVER_TYPE_WARP);
    if (FAILED(hr)) return hr;
    IDXGIDevice *dxgi = nullptr;
    hr = s_d3d->QueryInterface(__uuidof(IDXGIDevice), (void **)&dxgi);
    if (SUCCEEDED(hr)) hr = D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, __uuidof(ID2D1Factory1),
                                              nullptr, (void **)&s_factory);
    if (SUCCEEDED(hr)) hr = s_factory->CreateDevice(dxgi, &s_d2d);
    release(dxgi);
    if (SUCCEEDED(hr)) hr = DCompositionCreateDevice2(s_d2d, __uuidof(IDCompositionDevice), (void **)&s_device);
    return hr;
}

static void releaseDevices(void) {
    release(s_device);
    release(s_d2d);
    release(s_factory);
    release(s_d3d);
}

extern "C" void ionCompDetach(IonWinWindow *w) {
    auto *root = static_cast<IDCompositionVisual *>(w->compRoot);
    auto *target = static_cast<IDCompositionTarget *>(w->compTarget);
    if (target == nullptr) return;
    release(root);
    release(target);
    w->compRoot = nullptr;
    w->compTarget = nullptr;
    if (--s_targets == 0) releaseDevices();
    else s_device->Commit();
}

extern "C" int ionCompAttach(IonWinWindow *w) {
    HRESULT hr = s_device ? S_OK : createDevices();
    if (FAILED(hr)) {
        fprintf(stderr, "[ion] window compositor device setup failed: 0x%08lx\n", (long)hr);
        releaseDevices();
        return 0;
    }
    IDCompositionTarget *target = nullptr;
    IDCompositionVisual *root = nullptr;
    hr = s_device->CreateTargetForHwnd(w->hwnd, TRUE, &target);
    if (SUCCEEDED(hr)) hr = s_device->CreateVisual(&root);
    if (SUCCEEDED(hr)) hr = target->SetRoot(root);
    if (SUCCEEDED(hr)) hr = s_device->Commit();
    if (FAILED(hr)) {
        fprintf(stderr, "[ion] window %d compositor setup failed: 0x%08lx\n", (int)w->id, (long)hr);
        release(root);
        release(target);
        if (s_targets == 0) releaseDevices();
        return 0;
    }
    w->compTarget = target;
    w->compRoot = root;
    s_targets++;
    return 1;
}

extern "C" void *ionCompDevice(void) { return s_device; }

extern "C" void ionCompCommit(void) {
    if (s_device) s_device->Commit();
}

extern "C" void *ionWindowDevice(IonWindowId id) {
    return ionWinWindow(id) ? s_device : nullptr;
}

extern "C" void *ionWindowRoot(IonWindowId id) {
    IonWinWindow *w = ionWinWindow(id);
    return w ? w->compRoot : nullptr;
}

extern "C" void ionWindowCommit(IonWindowId id) {
    if (ionWinWindow(id)) ionCompCommit();
}
