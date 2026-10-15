#include "textFilter.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <string.h>

HWND ionGetMainHwnd(void);

void tfSend(int sys, int unit, int vk, int ctrl, int alt) {
    HWND hwnd = ionGetMainHwnd();
    BYTE saved[256], held[256];
    GetKeyboardState(saved);
    memcpy(held, saved, sizeof held);
    if (ctrl) held[VK_CONTROL] = held[VK_LCONTROL] = 0x80;
    if (alt) held[VK_MENU] = held[VK_LMENU] = 0x80;
    SetKeyboardState(held);
    if (vk) SendMessageW(hwnd, alt && !ctrl ? WM_SYSKEYDOWN : WM_KEYDOWN, (WPARAM)vk, 1);
    SendMessageW(hwnd, sys ? WM_SYSCHAR : WM_CHAR, (WPARAM)unit, sys ? (1 << 29) | 1 : 1);
    if (vk) SendMessageW(hwnd, alt && !ctrl ? WM_SYSKEYUP : WM_KEYUP, (WPARAM)vk, (LPARAM)0xC0000001);
    SetKeyboardState(saved);
}

void tfClose(void) { PostMessageW(ionGetMainHwnd(), WM_CLOSE, 0, 0); }
