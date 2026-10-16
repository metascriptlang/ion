#include "pointerMods.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <string.h>

HWND ionGetMainHwnd(void);

void pmClick(int shift, int x, int y) {
    HWND hwnd = ionGetMainHwnd();
    BYTE saved[256], held[256];
    GetKeyboardState(saved);
    memcpy(held, saved, sizeof held);
    held[VK_SHIFT] = held[VK_LSHIFT] = shift ? 0x80 : 0;
    SetKeyboardState(held);
    LPARAM at = MAKELPARAM(x, y);
    SendMessageW(hwnd, WM_MOUSEMOVE, shift ? MK_SHIFT : 0, at);
    SendMessageW(hwnd, WM_LBUTTONDOWN, MK_LBUTTON | (shift ? MK_SHIFT : 0), at);
    SendMessageW(hwnd, WM_LBUTTONUP, shift ? MK_SHIFT : 0, at);
    SetKeyboardState(saved);
}

void pmClose(void) { PostMessageW(ionGetMainHwnd(), WM_CLOSE, 0, 0); }
