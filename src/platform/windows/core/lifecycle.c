// Ion Windows — process lifecycle: ionInit / ionQuit + deep link bootstrap.
//
// ionInit handles three things native-side before MS user code resumes:
//   1. **Single-instance** — named mutex per .exe path. Secondary launches
//      forward their argv URL to the primary window via WM_COPYDATA, then
//      ExitProcess. Mac gets this automatically via LSGetApplicationForURL.
//   2. **Cold-start deep link** — if argv contains a `scheme://...` URL
//      (registered scheme launched the app), stash it in s_coldStartUrl.
//      Replayed as a "deeplink" IPC after the window is created
//      (see core/window.c ionOpen).
//   3. **HINSTANCE** — needed for window class registration.

#include "../state.h"
#include "../utf8.h"
#include "../../common/queue.h"
#include "../../bridge.h"

#include <shellapi.h>  // CommandLineToArgvW
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Match the window class registered in core/window.c — used by secondary
// instances to find the primary's HWND.
static const wchar_t kMainWindowClass[] = L"IonMainWindow";

// Custom WM_COPYDATA marker so we can tell our deep-link forwards apart
// from any other COPYDATA traffic (extremely unlikely but cheap to guard).
#define ION_COPYDATA_DEEPLINK  0x494f4e44  /* 'IOND' */

// Does this string look like a URL scheme (any letter+digit+`://` shape)?
static int isUrlArg(const wchar_t *arg) {
    if (arg == NULL) return 0;
    return wcsstr(arg, L"://") != NULL;
}

// Pull the first URL-shaped arg from argv into s_coldStartUrl.
static void captureColdStartUrl(void) {
    int argc = 0;
    LPWSTR *argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    if (argv == NULL) return;
    for (int i = 1; i < argc; i++) {
        if (isUrlArg(argv[i])) {
            ionWideToUtf8(argv[i], s_coldStartUrl, (int)sizeof(s_coldStartUrl));
            break;
        }
    }
    LocalFree(argv);
}

// Build a mutex name unique to this .exe path so two separate ion-based apps
// don't collide. Per-machine `Local\` namespace — fine for v0 (per-machine
// install). Returns 1 on success.
static int buildMutexName(wchar_t *out, size_t outCap) {
    wchar_t exePath[MAX_PATH];
    DWORD n = GetModuleFileNameW(NULL, exePath, MAX_PATH);
    if (n == 0 || n >= MAX_PATH) return 0;

    // Strip directory, keep basename without `.exe`.
    wchar_t *sep = wcsrchr(exePath, L'\\');
    wchar_t *base = sep ? sep + 1 : exePath;
    wchar_t *dot = wcsrchr(base, L'.');
    if (dot != NULL) *dot = L'\0';

    _snwprintf_s(out, outCap, _TRUNCATE, L"Local\\Ion-SingleInstance-%ls", base);
    return 1;
}

// Forward s_coldStartUrl to the already-running primary, then exit. Called
// only when our mutex acquisition saw ERROR_ALREADY_EXISTS.
static void forwardToPrimaryAndExit(void) {
    HWND primary = FindWindowW(kMainWindowClass, NULL);
    if (primary != NULL) {
        if (s_coldStartUrl[0] != '\0') {
            COPYDATASTRUCT cds;
            cds.dwData = ION_COPYDATA_DEEPLINK;
            cds.cbData = (DWORD)(strlen(s_coldStartUrl) + 1);
            cds.lpData = s_coldStartUrl;
            SendMessageW(primary, WM_COPYDATA, 0, (LPARAM)&cds);
        }
        // Always raise the existing window — clicking the icon a second time
        // should surface the running instance even without a URL.
        ShowWindow(primary, SW_SHOWNORMAL);
        SetForegroundWindow(primary);
    }
    ExitProcess(0);
}

int ionInit(void) {
    if (s_hInstance == NULL) {
        s_hInstance = GetModuleHandleW(NULL);
    }
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);

    captureColdStartUrl();

    // Single-instance gate. Mutex stays alive for the process lifetime;
    // OS reclaims on ExitProcess. We never close it explicitly because
    // ionQuit can run mid-shutdown when releasing is more risk than help.
    wchar_t mutexName[MAX_PATH];
    if (buildMutexName(mutexName, MAX_PATH)) {
        HANDLE m = CreateMutexW(NULL, FALSE, mutexName);
        if (m != NULL && GetLastError() == ERROR_ALREADY_EXISTS) {
            forwardToPrimaryAndExit();  // does not return
        }
    }

    return s_hInstance != NULL ? 1 : 0;
}

void ionQuit(void) {
    // Webview teardown happens in window.c's WM_DESTROY handler — by the
    // time ionQuit runs, the HWND (and any WebView2 attached to it) is
    // already gone. Nothing to release here beyond clearing the HINSTANCE.
    s_hInstance = NULL;
}
