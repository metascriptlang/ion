#include "servicesWindows.h"

#include <windows.h>

HWND ionWinHwnd(int id);

int swFocus(int window) {
    HWND h = ionWinHwnd(window), f = GetFocus();
    if (f == h) return 1;
    return f != NULL && IsChild(h, f) ? 2 : 0;
}

int swActive(int window) { return GetActiveWindow() == ionWinHwnd(window) ? 1 : 0; }
