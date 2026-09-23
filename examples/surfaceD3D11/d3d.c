#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <stdio.h>

static ID3D11Device           *s_device;
static ID3D11DeviceContext    *s_context;
static IDXGISwapChain1        *s_swapChain;
static ID3D11RenderTargetView *s_rtv;

static int makeTarget(void) {
    ID3D11Texture2D *back = NULL;
    HRESULT hr = IDXGISwapChain1_GetBuffer(s_swapChain, 0, &IID_ID3D11Texture2D, (void **)&back);
    if (FAILED(hr)) return 0;
    hr = ID3D11Device_CreateRenderTargetView(s_device, (ID3D11Resource *)back, NULL, &s_rtv);
    ID3D11Texture2D_Release(back);
    return SUCCEEDED(hr);
}

long long demoD3DCreate(int width, int height) {
    D3D_FEATURE_LEVEL level;
    HRESULT hr = D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, D3D11_CREATE_DEVICE_BGRA_SUPPORT,
                                   NULL, 0, D3D11_SDK_VERSION, &s_device, &level, &s_context);
    if (FAILED(hr)) { fprintf(stderr, "demo: D3D11CreateDevice 0x%08lx\n", (long)hr); return 0; }

    IDXGIDevice *dxgiDevice = NULL;
    IDXGIAdapter *adapter = NULL;
    IDXGIFactory2 *factory = NULL;
    ID3D11Device_QueryInterface(s_device, &IID_IDXGIDevice, (void **)&dxgiDevice);
    IDXGIDevice_GetAdapter(dxgiDevice, &adapter);
    IDXGIAdapter_GetParent(adapter, &IID_IDXGIFactory2, (void **)&factory);

    DXGI_SWAP_CHAIN_DESC1 desc;
    ZeroMemory(&desc, sizeof desc);
    desc.Width = (UINT)(width > 0 ? width : 1);
    desc.Height = (UINT)(height > 0 ? height : 1);
    desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    desc.SampleDesc.Count = 1;
    desc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    desc.BufferCount = 2;
    desc.Scaling = DXGI_SCALING_STRETCH;
    desc.SwapEffect = DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL;
    desc.AlphaMode = DXGI_ALPHA_MODE_PREMULTIPLIED;
    hr = IDXGIFactory2_CreateSwapChainForComposition(factory, (IUnknown *)s_device, &desc, NULL, &s_swapChain);
    IDXGIFactory2_Release(factory);
    IDXGIAdapter_Release(adapter);
    IDXGIDevice_Release(dxgiDevice);
    if (FAILED(hr)) { fprintf(stderr, "demo: CreateSwapChainForComposition 0x%08lx\n", (long)hr); return 0; }
    if (!makeTarget()) return 0;
    return (long long)(intptr_t)s_swapChain;
}

void demoD3DResize(int width, int height) {
    if (s_swapChain == NULL || width <= 0 || height <= 0) return;
    ID3D11DeviceContext_OMSetRenderTargets(s_context, 0, NULL, NULL);
    if (s_rtv) { ID3D11RenderTargetView_Release(s_rtv); s_rtv = NULL; }
    HRESULT hr = IDXGISwapChain1_ResizeBuffers(s_swapChain, 0, (UINT)width, (UINT)height, DXGI_FORMAT_UNKNOWN, 0);
    if (FAILED(hr)) { fprintf(stderr, "demo: ResizeBuffers 0x%08lx\n", (long)hr); return; }
    makeTarget();
}

void demoD3DClear(double r, double g, double b) {
    if (s_rtv == NULL) return;
    const FLOAT color[4] = { (FLOAT)r, (FLOAT)g, (FLOAT)b, 1.0f };
    ID3D11DeviceContext_ClearRenderTargetView(s_context, s_rtv, color);
    IDXGISwapChain1_Present(s_swapChain, 1, 0);
}
