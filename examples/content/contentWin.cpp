#include "content.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <dcomp.h>
#include <d2d1_1.h>
#include <dwrite.h>
#include <cstdio>
#include <cstdlib>

static IDWriteFactory *s_write = nullptr;

static IDWriteFactory *writeFactory(void) {
    if (s_write == nullptr &&
        FAILED(DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory), (IUnknown **)&s_write)))
        fprintf(stderr, "[content] DWriteCreateFactory failed\n");
    return s_write;
}

extern "C" int contentAttach(void *parent, void *child, int above) {
    if (parent == nullptr || child == nullptr) return 0;
    // With a NULL reference DirectComposition inverts insertAbove: FALSE puts
    // the child in front of every sibling, TRUE behind them (measured 2026-10-15).
    HRESULT hr = static_cast<IDCompositionVisual *>(parent)->AddVisual(
        static_cast<IDCompositionVisual *>(child), above ? FALSE : TRUE, nullptr);
    if (FAILED(hr)) fprintf(stderr, "[content] AddVisual failed: 0x%08lx\n", (long)hr);
    return SUCCEEDED(hr);
}

extern "C" void contentDetach(void *parent, void *child) {
    if (parent != nullptr && child != nullptr)
        static_cast<IDCompositionVisual *>(parent)->RemoveVisual(static_cast<IDCompositionVisual *>(child));
}

extern "C" void contentMove(void *node, int x, int y, int w, int h) {
    (void)w; (void)h;
    if (node == nullptr) return;
    auto *visual = static_cast<IDCompositionVisual *>(node);
    visual->SetOffsetX((float)x);
    visual->SetOffsetY((float)y);
}

static wchar_t *wide(const char *utf8) {
    int n = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, nullptr, 0);
    auto *w = (wchar_t *)malloc(sizeof(wchar_t) * (size_t)(n > 0 ? n : 1));
    if (w != nullptr) MultiByteToWideChar(CP_UTF8, 0, utf8, -1, w, n);
    return w;
}

static void draw(ID2D1DeviceContext *dc, POINT at, int w, int h, const char *text, unsigned rgb) {
    dc->SetTransform(D2D1::Matrix3x2F::Translation((float)at.x, (float)at.y));
    dc->Clear(D2D1::ColorF(0, 0.0f));
    ID2D1SolidColorBrush *fill = nullptr, *ink = nullptr;
    dc->CreateSolidColorBrush(D2D1::ColorF(rgb), &fill);
    dc->CreateSolidColorBrush(D2D1::ColorF(D2D1::ColorF::White), &ink);
    D2D1_ROUNDED_RECT shape = { D2D1::RectF(0, 0, (float)w, (float)h), 18.0f, 18.0f };
    if (fill) dc->FillRoundedRectangle(shape, fill);
    IDWriteTextFormat *format = nullptr;
    IDWriteFactory *factory = writeFactory();
    if (factory && SUCCEEDED(factory->CreateTextFormat(L"Segoe UI", nullptr, DWRITE_FONT_WEIGHT_SEMI_BOLD,
            DWRITE_FONT_STYLE_NORMAL, DWRITE_FONT_STRETCH_NORMAL, 22.0f, L"en-us", &format))) {
        format->SetTextAlignment(DWRITE_TEXT_ALIGNMENT_CENTER);
        format->SetParagraphAlignment(DWRITE_PARAGRAPH_ALIGNMENT_CENTER);
        wchar_t *wtext = wide(text);
        if (wtext && ink) dc->DrawText(wtext, (UINT32)wcslen(wtext), format, D2D1::RectF(0, 0, (float)w, (float)h), ink);
        free(wtext);
        format->Release();
    }
    if (fill) fill->Release();
    if (ink) ink->Release();
}

extern "C" void *contentPanel(void *device, int w, int h, const char *text, unsigned rgb) {
    auto *dev = static_cast<IDCompositionDevice *>(device);
    if (dev == nullptr || w <= 0 || h <= 0) return nullptr;
    IDCompositionVisual *visual = nullptr;
    IDCompositionSurface *surface = nullptr;
    HRESULT hr = dev->CreateVisual(&visual);
    if (SUCCEEDED(hr)) hr = dev->CreateSurface((UINT)w, (UINT)h, DXGI_FORMAT_B8G8R8A8_UNORM,
                                               DXGI_ALPHA_MODE_PREMULTIPLIED, &surface);
    ID2D1DeviceContext *dc = nullptr;
    POINT at = { 0, 0 };
    if (SUCCEEDED(hr)) hr = surface->BeginDraw(nullptr, __uuidof(ID2D1DeviceContext), (void **)&dc, &at);
    if (SUCCEEDED(hr)) {
        draw(dc, at, w, h, text, rgb);
        dc->Release();
        hr = surface->EndDraw();
    }
    if (SUCCEEDED(hr)) hr = visual->SetContent(surface);
    if (surface) surface->Release();
    if (FAILED(hr)) {
        fprintf(stderr, "[content] panel '%s' failed: 0x%08lx\n", text, (long)hr);
        if (visual) visual->Release();
        return nullptr;
    }
    return visual;
}

extern "C" void contentRelease(void *node) {
    if (node != nullptr) static_cast<IDCompositionVisual *>(node)->Release();
}
