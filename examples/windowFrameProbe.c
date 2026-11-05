#include "windowFrameProbe.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

HWND ionWinHwnd(int id);

int wpPixel(int window, int x, int y) {
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

int wpZoomed(int window) { return IsZoomed(ionWinHwnd(window)) ? 1 : 0; }
int wpVisible(int window) { return IsWindowVisible(ionWinHwnd(window)) ? 1 : 0; }

// Sends the WM_SIZING a bottom-right drag to an off-grid size would, then checks the client size
// the window proc left in the rect.
int wpSteps(int window, int cellW, int cellH, int baseW, int baseH) {
    HWND h = ionWinHwnd(window);
    RECT outer, client;
    if (h == NULL || !GetWindowRect(h, &outer) || !GetClientRect(h, &client)) return 0;
    int decoW = (outer.right - outer.left) - client.right, decoH = (outer.bottom - outer.top) - client.bottom;
    RECT r = {outer.left, outer.top, outer.left + decoW + baseW + 7 * cellW + cellW / 3,
              outer.top + decoH + baseH + 5 * cellH + cellH * 2 / 3};
    SendMessageW(h, WM_SIZING, WMSZ_BOTTOMRIGHT, (LPARAM)&r);
    int cw = r.right - r.left - decoW, ch = r.bottom - r.top - decoH;
    return r.left == outer.left && r.top == outer.top && cw == baseW + 7 * cellW && ch == baseH + 6 * cellH;
}

int wpOnScreen(int x, int y) {
    POINT p = {x, y};
    return MonitorFromPoint(p, MONITOR_DEFAULTTONULL) != NULL;
}
