#include "keyFields.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <string.h>

HWND ionGetMainHwnd(void);

static HKL s_loaded[4];
static int s_loadedCount;

static int installed(HKL hkl) {
    HKL list[64];
    int n = GetKeyboardLayoutList(64, list);
    for (int i = 0; i < n; i++) if (list[i] == hkl) return 1;
    return 0;
}

int kfLayout(const char *klid) {
    WCHAR w[16];
    MultiByteToWideChar(CP_UTF8, 0, klid, -1, w, 16);
    HKL before[64];
    int had = GetKeyboardLayoutList(64, before);
    HKL hkl = LoadKeyboardLayoutW(w, KLF_NOTELLSHELL);
    if (hkl == NULL) return 0;
    int known = 0;
    for (int i = 0; i < had; i++) if (before[i] == hkl) known = 1;
    if (!known && s_loadedCount < 4) s_loaded[s_loadedCount++] = hkl;
    return ActivateKeyboardLayout(hkl, 0) != NULL;
}

void kfUnloadLayouts(void) {
    for (int i = 0; i < s_loadedCount; i++) if (installed(s_loaded[i])) UnloadKeyboardLayout(s_loaded[i]);
    s_loadedCount = 0;
}

static void deliver(HWND hwnd, UINT msg, WPARAM vk, LPARAM lParam, int *chars) {
    MSG m;
    memset(&m, 0, sizeof m);
    m.hwnd = hwnd;
    m.message = msg;
    m.wParam = vk;
    m.lParam = lParam;
    TranslateMessage(&m);
    SendMessageW(hwnd, msg, vk, lParam);
    MSG q;
    while (PeekMessageW(&q, hwnd, WM_CHAR, WM_SYSDEADCHAR, PM_REMOVE)) {
        if (q.message == WM_CHAR || q.message == WM_SYSCHAR) (*chars)++;
        DispatchMessageW(&q);
    }
}

int kfKey(int vk, int ctrl, int shift, int alt, int altGr) {
    HWND hwnd = ionGetMainHwnd();
    BYTE saved[256], held[256];
    GetKeyboardState(saved);
    memcpy(held, saved, sizeof held);
    if (ctrl || altGr) held[VK_CONTROL] = held[VK_LCONTROL] = 0x80;
    if (shift) held[VK_SHIFT] = held[VK_LSHIFT] = 0x80;
    if (alt) held[VK_MENU] = held[VK_LMENU] = 0x80;
    if (altGr) held[VK_MENU] = held[VK_RMENU] = 0x80;
    held[vk & 0xff] = 0x80;
    SetKeyboardState(held);
    int sysKey = alt && !ctrl && !altGr;
    LPARAM down = (LPARAM)((MapVirtualKeyW((UINT)vk, MAPVK_VK_TO_VSC) << 16) | 1 | (sysKey ? (1 << 29) : 0));
    int chars = 0;
    deliver(hwnd, sysKey ? WM_SYSKEYDOWN : WM_KEYDOWN, (WPARAM)vk, down, &chars);
    held[vk & 0xff] = 0;
    SetKeyboardState(held);
    deliver(hwnd, sysKey ? WM_SYSKEYUP : WM_KEYUP, (WPARAM)vk, down | (LPARAM)0xC0000000, &chars);
    SetKeyboardState(saved);
    return chars;
}

void kfClose(void) { PostMessageW(ionGetMainHwnd(), WM_CLOSE, 0, 0); }
