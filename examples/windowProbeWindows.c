#include "windowProbeWindows.h"

#include <windows.h>

HWND ionWinHwnd(int id);
void ionWindowSetAutomation(int id, int (*getObject)(void *, unsigned long long, long long, long long *),
                            void (*disconnect)(void *));

#define UIA_ROOT_OBJECT_ID (-25)
#define HOOK_ANSWER 0x5157

void wpSysClose(int window) { SendMessageW(ionWinHwnd(window), WM_SYSCOMMAND, SC_CLOSE, 0); }

void wpAltF4(int window) {
    HWND h = ionWinHwnd(window);
    LPARAM bits = 1 | (0x3E << 16) | (1 << 29);
    SendMessageW(h, WM_SYSKEYDOWN, VK_F4, bits);
    SendMessageW(h, WM_SYSKEYUP, VK_F4, bits | (LPARAM)0xC0000000);
}

static void mouseAt(INPUT *in, POINT p, DWORD flags) {
    ZeroMemory(in, sizeof *in);
    in->type = INPUT_MOUSE;
    in->mi.dx = MulDiv(p.x - GetSystemMetrics(SM_XVIRTUALSCREEN), 65535, GetSystemMetrics(SM_CXVIRTUALSCREEN) - 1);
    in->mi.dy = MulDiv(p.y - GetSystemMetrics(SM_YVIRTUALSCREEN), 65535, GetSystemMetrics(SM_CYVIRTUALSCREEN) - 1);
    in->mi.dwFlags = flags | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK;
}

int wpClickClose(int window) {
    HWND h = ionWinHwnd(window);
    TITLEBARINFOEX info = { sizeof info };
    SendMessageW(h, WM_GETTITLEBARINFOEX, 0, (LPARAM)&info);
    RECT r = info.rgrect[5];
    POINT p = { (r.left + r.right) / 2, (r.top + r.bottom) / 2 };
    if (r.right <= r.left || GetAncestor(WindowFromPoint(p), GA_ROOT) != h) return 0;
    POINT back;
    GetCursorPos(&back);
    INPUT in[3];
    mouseAt(&in[0], p, MOUSEEVENTF_MOVE);
    mouseAt(&in[1], p, MOUSEEVENTF_LEFTDOWN);
    mouseAt(&in[2], p, MOUSEEVENTF_LEFTUP);
    UINT sent = SendInput(3, in, sizeof in[0]);
    SetCursorPos(back.x, back.y);
    return sent == 3 ? 1 : 0;
}

int wpWindowState(int window) {
    HWND h = ionWinHwnd(window);
    if (IsIconic(h)) return 2;
    return GetActiveWindow() == h ? 1 : 0;
}

static UINT s_shellHook = 0;
static HWND s_flashed[16];
static int s_flashCount = 0;

static LRESULT CALLBACK shellProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    if (msg == s_shellHook && wParam == HSHELL_FLASH && s_flashCount < 16) s_flashed[s_flashCount++] = (HWND)lParam;
    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

int wpWatchFlashes(void) {
    WNDCLASSW wc = {0};
    wc.lpfnWndProc = shellProc;
    wc.hInstance = GetModuleHandleW(NULL);
    wc.lpszClassName = L"IonProbeShellHook";
    RegisterClassW(&wc);
    HWND h = CreateWindowExW(WS_EX_TOOLWINDOW, wc.lpszClassName, L"", WS_POPUP, 0, 0, 0, 0, NULL, NULL, wc.hInstance, NULL);
    s_shellHook = RegisterWindowMessageW(L"SHELLHOOK");
    return h != NULL && s_shellHook != 0 && RegisterShellHookWindow(h) ? 1 : 0;
}

int wpFlashes(int window) {
    HWND h = ionWinHwnd(window);
    int n = 0;
    for (int i = 0; i < s_flashCount; i++) n += s_flashed[i] == h;
    return n;
}

static int s_hookCalls = 0;
static void *s_hookHwnd = NULL;
static long long s_hookObject = 0;
static int s_disconnects = 0;
static void *s_disconnectHwnd = NULL;
static HWND s_remembered = NULL;

static int hook(void *hwnd, unsigned long long wParam, long long lParam, long long *result) {
    (void)wParam;
    s_hookCalls++;
    s_hookHwnd = hwnd;
    s_hookObject = lParam;
    if ((LONG)lParam != UIA_ROOT_OBJECT_ID) return 0;
    *result = HOOK_ANSWER;
    return 1;
}

static void disconnect(void *hwnd) {
    s_disconnects++;
    s_disconnectHwnd = hwnd;
}

void wpInstallAutomation(int window) { ionWindowSetAutomation(window, hook, disconnect); }
void wpRemoveAutomation(int window) { ionWindowSetAutomation(window, NULL, NULL); }

int wpGetObject(int window, int objectId) {
    LRESULT r = SendMessageW(ionWinHwnd(window), WM_GETOBJECT, 0, (LPARAM)(LONG)objectId);
    if (r == HOOK_ANSWER) return 1;
    return r != 0 ? 2 : 0;
}

int wpHookCalls(void) { return s_hookCalls; }
int wpHookSaw(int window, int objectId) {
    return s_hookHwnd == (void *)ionWinHwnd(window) && (LONG)s_hookObject == objectId ? 1 : 0;
}
int wpDisconnects(void) { return s_disconnects; }
void wpRemember(int window) { s_remembered = ionWinHwnd(window); }
int wpDisconnectedRemembered(void) { return s_remembered != NULL && s_disconnectHwnd == (void *)s_remembered ? 1 : 0; }
