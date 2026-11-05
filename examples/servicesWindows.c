#include "servicesWindows.h"

#include <windows.h>
#include <commctrl.h>
#include <shlwapi.h>
#include <stdio.h>
#include <string.h>

HWND ionWinHwnd(int id);

int swFocus(int window) {
    HWND h = ionWinHwnd(window), f = GetFocus();
    if (f == h) return 1;
    return f != NULL && IsChild(h, f) ? 2 : 0;
}

int swActive(int window) { return GetActiveWindow() == ionWinHwnd(window) ? 1 : 0; }

int swManifestNamesCommonControls(void) {
    HRSRC r = FindResourceW(NULL, MAKEINTRESOURCEW(1), MAKEINTRESOURCEW(24));
    if (r == NULL) return 0;
    const char *bytes = (const char *)LockResource(LoadResource(NULL, r));
    DWORD size = SizeofResource(NULL, r);
    const char *needle = "Microsoft.Windows.Common-Controls";
    size_t n = strlen(needle);
    for (DWORD i = 0; bytes != NULL && i + n <= size; i++) {
        if (memcmp(bytes + i, needle, n) == 0) return 1;
    }
    return 0;
}

int swTaskDialogComctlMajor(void) {
    HMODULE m = LoadLibraryW(L"comctl32.dll");
    if (m == NULL || GetProcAddress(m, "TaskDialogIndirect") == NULL) return 0;
    DLLGETVERSIONPROC getVersion = (DLLGETVERSIONPROC)(void *)GetProcAddress(m, "DllGetVersion");
    DLLVERSIONINFO info = {0};
    info.cbSize = sizeof(info);
    return getVersion != NULL && SUCCEEDED(getVersion(&info)) ? (int)info.dwMajorVersion : 0;
}

static int s_answerId = 0;
static int s_triesLeft = 0;
static char s_seen[256] = "";

static BOOL CALLBACK findDialog(HWND h, LPARAM out) {
    wchar_t cls[64];
    if (IsWindowVisible(h) && GetClassNameW(h, cls, 64) && wcscmp(cls, L"#32770") == 0) {
        *(HWND *)out = h;
        return FALSE;
    }
    return TRUE;
}

static void CALLBACK answer(HWND unused, UINT msg, UINT_PTR timer, DWORD time) {
    (void)unused; (void)msg; (void)time;
    HWND dialog = NULL;
    EnumThreadWindows(GetCurrentThreadId(), findDialog, (LPARAM)&dialog);
    if (dialog == NULL) {
        if (--s_triesLeft <= 0) KillTimer(NULL, timer);
        return;
    }
    KillTimer(NULL, timer);
    wchar_t title[128];
    char utf8[128];
    GetWindowTextW(dialog, title, 128);
    WideCharToMultiByte(CP_UTF8, 0, title, -1, utf8, sizeof(utf8), NULL, NULL);
    snprintf(s_seen, sizeof(s_seen), "#32770:%s", utf8);
    if (s_answerId != 0) PostMessageW(dialog, TDM_CLICK_BUTTON, (WPARAM)s_answerId, 0);
    else PostMessageW(dialog, WM_CLOSE, 0, 0);
}

void swAnswerDialogAfter(int ms, int id) {
    s_answerId = id;
    s_triesLeft = 50;
    s_seen[0] = '\0';
    SetTimer(NULL, 0, (UINT)ms, answer);
}

const char *swDialogSeen(void) { return s_seen; }
