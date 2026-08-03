// Ion Windows — OS notifications via Shell_NotifyIcon balloon tip.
//
// Win32 surface: a separate hidden Shell_NotifyIcon entry (NIS_HIDDEN — no
// extra tray icon visible) with NIM_MODIFY + NIF_INFO to surface the
// balloon. Windows 10/11 renders these through the Toast / Action Center
// pipeline, so users see a modern UI even though we use the legacy API.
//
// We deliberately do NOT use Toast WinRT (ToastNotificationManager): Toast
// requires an AUMID bound to a Start Menu shortcut, which only exists after
// the NSIS installer in Phase 5 runs. Balloon works standalone. Phase 5
// upgrades.
//
// Callback message (WM_ION_NOTIFY_CB / WM_APP+2) routes to the main HWND's
// WndProc — see comment in chrome/tray.c about why we don't use a private
// HWND_MESSAGE window.

#include "../state.h"
#include "../utf8.h"
#include "../internal.h"
#include "../../bridge.h"

#include <shellapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ION_NOTIFY_UID    2

static NOTIFYICONDATAW  s_notifyNid    = {0};
static int              s_notifyAdded  = 0;

// Last-emitted notification ID — replayed as the payload of the next
// balloon click. Win32 balloons don't carry per-instance context, so the
// "single in-flight" assumption matches typical app UX (one toast at a time).
static char             s_lastNotifId[128] = {0};

void ionNotifyHandleCallback(UINT event) {
    if (event == NIN_BALLOONUSERCLICK) {
        ionEnqueueMessage("notification.click", s_lastNotifId);
        if (s_mainHwnd != NULL) {
            ShowWindow(s_mainHwnd, SW_SHOWNORMAL);
            SetForegroundWindow(s_mainHwnd);
        }
    }
}

static int ensureNotifyEntry(void) {
    if (s_notifyAdded) return 1;
    if (s_mainHwnd == NULL) return 0;

    memset(&s_notifyNid, 0, sizeof(s_notifyNid));
    s_notifyNid.cbSize           = sizeof(s_notifyNid);
    s_notifyNid.hWnd             = s_mainHwnd;
    s_notifyNid.uID              = ION_NOTIFY_UID;
    s_notifyNid.uFlags           = NIF_ICON | NIF_MESSAGE | NIF_STATE;
    s_notifyNid.uCallbackMessage = WM_ION_NOTIFY_CB;
    s_notifyNid.hIcon            = LoadIconW(NULL, IDI_INFORMATION);
    s_notifyNid.dwState          = NIS_HIDDEN;
    s_notifyNid.dwStateMask      = NIS_HIDDEN;

    if (Shell_NotifyIconW(NIM_ADD, &s_notifyNid) == FALSE) return 0;
    s_notifyAdded = 1;
    return 1;
}

void ionNotify(const char *title, const char *body, const char *id) {
    if (!ensureNotifyEntry()) return;

    s_lastNotifId[0] = '\0';
    if (id != NULL && id[0] != '\0') {
        strncpy_s(s_lastNotifId, sizeof(s_lastNotifId), id, _TRUNCATE);
    } else {
        strncpy_s(s_lastNotifId, sizeof(s_lastNotifId), "ion-notif", _TRUNCATE);
    }

    s_notifyNid.uFlags      = NIF_INFO;
    s_notifyNid.dwInfoFlags = NIIF_INFO;

    wchar_t *wtitle = ionUtf8ToWide(title != NULL ? title : "");
    wchar_t *wbody  = ionUtf8ToWide(body  != NULL ? body  : "");

    s_notifyNid.szInfoTitle[0] = L'\0';
    s_notifyNid.szInfo[0]      = L'\0';
    if (wtitle != NULL) {
        wcsncpy_s(s_notifyNid.szInfoTitle,
                  sizeof(s_notifyNid.szInfoTitle) / sizeof(wchar_t),
                  wtitle, _TRUNCATE);
        free(wtitle);
    }
    if (wbody != NULL) {
        wcsncpy_s(s_notifyNid.szInfo,
                  sizeof(s_notifyNid.szInfo) / sizeof(wchar_t),
                  wbody, _TRUNCATE);
        free(wbody);
    }

    Shell_NotifyIconW(NIM_MODIFY, &s_notifyNid);
}
