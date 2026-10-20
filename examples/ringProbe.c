#include "ringProbe.h"
#include <windows.h>
#include <stdio.h>

static HWND s_hwnd;
static WNDPROC s_orig;
static HANDLE s_entered, s_exited;
static volatile LONG s_done, s_moves;
static int s_burst;

static LRESULT CALLBACK probeProc(HWND h, UINT m, WPARAM w, LPARAM l) {
    if (m == WM_ENTERSIZEMOVE) SetEvent(s_entered);
    if (m == WM_MOVE) InterlockedIncrement(&s_moves);
    LRESULT r = CallWindowProcW(s_orig, h, m, w, l);
    if (m == WM_EXITSIZEMOVE) SetEvent(s_exited);
    return r;
}

static void postKey(WORD vk) {
    PostMessageW(s_hwnd, WM_KEYDOWN, vk, 0);
    PostMessageW(s_hwnd, WM_KEYUP, vk, 0);
}

static DWORD WINAPI driver(void *arg) {
    (void)arg;
    POINT cursor;
    GetCursorPos(&cursor);
    PostMessageW(s_hwnd, WM_SYSCOMMAND, SC_MOVE, 0);
    if (WaitForSingleObject(s_entered, 1000) != WAIT_OBJECT_0) {
        printf("ringProbe: no WM_ENTERSIZEMOVE\n");
    } else {
        RECT r0;
        GetWindowRect(s_hwnd, &r0);
        for (int i = 0; i < 500; i++) {
            SetWindowPos(s_hwnd, NULL, r0.left + (i % 50), r0.top, 0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
            if (s_burst == 0) Sleep(2);
        }
        postKey(VK_ESCAPE);
        WaitForSingleObject(s_exited, 2000);
        printf("ringProbe: WM_MOVE seen by the window %ld\n", s_moves);
    }
    SetCursorPos(cursor.x, cursor.y);
    RECT r;
    GetWindowRect(s_hwnd, &r);
    SetWindowPos(s_hwnd, NULL, 0, 0, 640, 420, SWP_NOMOVE | SWP_NOZORDER);
    fflush(stdout);
    InterlockedExchange(&s_done, 1);
    return 0;
}

int ringInit(void) {
    s_burst = GetEnvironmentVariableA("RING_BURST", NULL, 0) > 0;
    s_hwnd = FindWindowW(NULL, L"Ion ring probe");
    if (s_hwnd == NULL) return 0;
    s_entered = CreateEventW(NULL, TRUE, FALSE, NULL);
    s_exited = CreateEventW(NULL, TRUE, FALSE, NULL);
    s_orig = (WNDPROC)SetWindowLongPtrW(s_hwnd, GWLP_WNDPROC, (LONG_PTR)probeProc);
    return 1;
}

void ringRun(void) {
    HANDLE t = CreateThread(NULL, 0, driver, NULL, 0, NULL);
    if (t != NULL) CloseHandle(t);
}

int ringDone(void) { return (int)s_done; }
