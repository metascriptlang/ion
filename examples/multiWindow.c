#include "multiWindow.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

HWND ionWinHwnd(int id);

void mwClick(int window, int x, int y) {
    HWND h = ionWinHwnd(window);
    PostMessageW(h, WM_MOUSEMOVE, 0, MAKELPARAM(x, y));
    PostMessageW(h, WM_LBUTTONDOWN, MK_LBUTTON, MAKELPARAM(x, y));
    PostMessageW(h, WM_LBUTTONUP, 0, MAKELPARAM(x, y));
}

void mwKey(int window, int vk, int scancode) {
    HWND h = ionWinHwnd(window);
    PostMessageW(h, WM_KEYDOWN, (WPARAM)vk, (LPARAM)(1 | (scancode << 16)));
    PostMessageW(h, WM_KEYUP, (WPARAM)vk, (LPARAM)(1 | (scancode << 16) | 0xC0000000u));
}

void mwClose(int window) {
    PostMessageW(ionWinHwnd(window), WM_CLOSE, 0, 0);
}

int mwPixel(int window, int x, int y) {
    HWND h = ionWinHwnd(window);
    RECT rc;
    if (h == NULL || !GetWindowRect(h, &rc)) return -1;
    int w = rc.right - rc.left, ht = rc.bottom - rc.top;
    POINT origin = {0, 0};
    ClientToScreen(h, &origin);
    HDC screen = GetDC(NULL);
    HDC mem = CreateCompatibleDC(screen);
    HBITMAP bmp = CreateCompatibleBitmap(screen, w, ht);
    HGDIOBJ old = SelectObject(mem, bmp);
    int out = -1;
    if (PrintWindow(h, mem, PW_RENDERFULLCONTENT)) {
        COLORREF c = GetPixel(mem, origin.x - rc.left + x, origin.y - rc.top + y);
        if (c != CLR_INVALID) out = (int)((GetRValue(c) << 16) | (GetGValue(c) << 8) | GetBValue(c));
    }
    SelectObject(mem, old);
    DeleteObject(bmp);
    DeleteDC(mem);
    ReleaseDC(NULL, screen);
    return out;
}
