// Ion Windows — system tray (notification area) icon.
//
// Win32 surface: Shell_NotifyIconW. Callback messages (uCallbackMessage =
// WM_ION_TRAY_CB / WM_APP+1) route to the main HWND's WndProc in
// core/window.c, which calls `ionTrayHandleCallback(event)` here.
//
// We deliberately don't use a private HWND_MESSAGE window for callbacks —
// Shell_NotifyIcon does not reliably deliver to message-only windows on
// Windows 10/11. Routing through the main visible window is the standard
// pattern + matches what wails / Tauri do internally.
//
// Asset path resolution mirrors mac: try the literal path first; if that
// fails, look up <basename> under <exe-dir>/resources/ via ionResourcePath().
// Final fallback is the default IDI_APPLICATION icon so the tray stays
// visible rather than vanishing on a bad path.

#include "../state.h"
#include "../utf8.h"
#include "../internal.h"
#include "../../bridge.h"

#include <shellapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ION_TRAY_UID    1

static NOTIFYICONDATAW  s_trayNid       = {0};
static HICON            s_trayIconOwned = NULL;   // freed via DestroyIcon
static int              s_trayInstalled = 0;

void ionTrayHandleCallback(UINT event) {
    if (event == WM_LBUTTONUP) {
        ionEnqueueMessage("tray.click", "");
        if (s_mainHwnd != NULL) {
            ShowWindow(s_mainHwnd, SW_SHOWNORMAL);
            SetForegroundWindow(s_mainHwnd);
        }
    }
}

// Load tray icon from a UTF-8 path. Falls back to looking the basename up
// under <exe-dir>/resources/. Returns NULL if both attempts fail; caller
// substitutes IDI_APPLICATION.
static HICON loadTrayIconFromPath(const char *pathUtf8) {
    if (pathUtf8 == NULL || pathUtf8[0] == '\0') return NULL;

    wchar_t *wpath = ionUtf8ToWide(pathUtf8);
    if (wpath != NULL) {
        HICON h = (HICON)LoadImageW(NULL, wpath, IMAGE_ICON, 16, 16,
                                    LR_LOADFROMFILE | LR_DEFAULTSIZE);
        free(wpath);
        if (h != NULL) return h;
    }

    const char *resDir = msStringToCString(ionResourcePath());
    if (resDir != NULL && resDir[0] != '\0') {
        const char *base = pathUtf8;
        for (const char *p = pathUtf8; *p != '\0'; p++) {
            if (*p == '/' || *p == '\\') base = p + 1;
        }
        char composed[1024];
        snprintf(composed, sizeof(composed), "%s\\%s", resDir, base);
        wchar_t *wcomp = ionUtf8ToWide(composed);
        if (wcomp != NULL) {
            HICON h = (HICON)LoadImageW(NULL, wcomp, IMAGE_ICON, 16, 16,
                                        LR_LOADFROMFILE | LR_DEFAULTSIZE);
            free(wcomp);
            if (h != NULL) return h;
        }
    }
    return NULL;
}

static void primeTrayNid(HICON icon, const wchar_t *tipOrNull) {
    memset(&s_trayNid, 0, sizeof(s_trayNid));
    s_trayNid.cbSize           = sizeof(s_trayNid);
    s_trayNid.hWnd             = s_mainHwnd;
    s_trayNid.uID              = ION_TRAY_UID;
    s_trayNid.uFlags           = NIF_ICON | NIF_MESSAGE | NIF_TIP;
    s_trayNid.uCallbackMessage = WM_ION_TRAY_CB;
    s_trayNid.hIcon            = icon;
    if (tipOrNull != NULL) {
        wcsncpy_s(s_trayNid.szTip,
                  sizeof(s_trayNid.szTip) / sizeof(wchar_t),
                  tipOrNull, _TRUNCATE);
    }
}

void ionInstallTray(const char *title) {
    if (s_mainHwnd == NULL) return;

    HICON defaultIcon = LoadIconW(NULL, IDI_APPLICATION);
    if (s_trayIconOwned != NULL) {
        DestroyIcon(s_trayIconOwned);
        s_trayIconOwned = NULL;
    }

    wchar_t *wtitle = NULL;
    if (title != NULL && title[0] != '\0') wtitle = ionUtf8ToWide(title);
    primeTrayNid(defaultIcon, wtitle != NULL ? wtitle : L"ion");
    if (wtitle != NULL) free(wtitle);

    Shell_NotifyIconW(s_trayInstalled ? NIM_MODIFY : NIM_ADD, &s_trayNid);
    s_trayInstalled = 1;
}

void ionInstallTrayImage(const char *pngPath) {
    if (s_mainHwnd == NULL) return;

    HICON icon = loadTrayIconFromPath(pngPath);
    int iconIsOwned = (icon != NULL);  // we LoadImageW'd it, we own it
    if (icon == NULL) {
        icon = LoadIconW(NULL, IDI_APPLICATION);  // shared system resource
    }

    if (s_trayIconOwned != NULL) {
        DestroyIcon(s_trayIconOwned);
        s_trayIconOwned = NULL;
    }
    if (iconIsOwned) s_trayIconOwned = icon;

    primeTrayNid(icon, NULL);
    Shell_NotifyIconW(s_trayInstalled ? NIM_MODIFY : NIM_ADD, &s_trayNid);
    s_trayInstalled = 1;
}

void ionUninstallTray(void) {
    if (s_trayInstalled) {
        Shell_NotifyIconW(NIM_DELETE, &s_trayNid);
        s_trayInstalled = 0;
    }
    if (s_trayIconOwned != NULL) {
        DestroyIcon(s_trayIconOwned);
        s_trayIconOwned = NULL;
    }
}
