// Ion Windows — native file open dialog via IFileOpenDialog (COM), and messageBox via
// TaskDialogIndirect, which only Common Controls v6 exports (core/manifest.c selects it).
//
// Modal Show() — blocks the caller's message pump like mac NSOpenPanel does.
// Mirrors mac webview/macos/chrome/dialog.m: single-file selection, no type
// filter in v0, returns user-cancel as "".
//
// COM is initialized as STA (apartment-threaded). WebView2 likely already
// initialized it on this thread, but CoInitializeEx is reference-counted —
// the duplicate call is safe and returns S_FALSE. We do NOT pair it with
// CoUninitialize because the runtime expects COM to stay live for WebView2.

#include "../state.h"
#include "../utf8.h"
#include "../internal.h"
#include "../../bridge.h"
#include "../../common/strconv.h"

// COBJMACROS lets us call COM methods via `IFoo_Method(pInstance, ...)`
// helper macros, which keeps the C-style vtable invocations readable.
#define COBJMACROS
#include <shobjidl.h>
#include <commctrl.h>
#include <objbase.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Cached path from the most recent successful pick. Valid until the next
// ionFileOpen call (matches mac's s_lastFilePath lifetime contract).
static char s_lastFilePath[1024] = {0};

msString ionFileOpen(void) {
    return ionWinFileOpen(s_mainHwnd);
}

msString ionWinFileOpen(HWND parent) {
    s_lastFilePath[0] = '\0';

    HRESULT hrInit = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    if (FAILED(hrInit) && hrInit != RPC_E_CHANGED_MODE) return MS_EMPTY_STRING;

    IFileOpenDialog *pDialog = NULL;
    HRESULT hr = CoCreateInstance(
        &CLSID_FileOpenDialog, NULL, CLSCTX_INPROC_SERVER,
        &IID_IFileOpenDialog, (void **)&pDialog);
    if (FAILED(hr) || pDialog == NULL) return MS_EMPTY_STRING;

    // Show modal on `parent` so the dialog activates on top of that
    // window + blocks input to it (standard parent-child modal flow).
    hr = IFileOpenDialog_Show(pDialog, parent);
    if (hr == HRESULT_FROM_WIN32(ERROR_CANCELLED) || FAILED(hr)) {
        IFileOpenDialog_Release(pDialog);
        return MS_EMPTY_STRING;
    }

    IShellItem *pItem = NULL;
    hr = IFileOpenDialog_GetResult(pDialog, &pItem);
    if (FAILED(hr) || pItem == NULL) {
        IFileOpenDialog_Release(pDialog);
        return MS_EMPTY_STRING;
    }

    LPWSTR pszPathW = NULL;
    hr = IShellItem_GetDisplayName(pItem, SIGDN_FILESYSPATH, &pszPathW);
    if (SUCCEEDED(hr) && pszPathW != NULL) {
        ionWideToUtf8(pszPathW, s_lastFilePath, (int)sizeof(s_lastFilePath));
        CoTaskMemFree(pszPathW);
    }

    IShellItem_Release(pItem);
    IFileOpenDialog_Release(pDialog);
    return cStringToMs(s_lastFilePath);
}

#define ION_MESSAGE_BOX_FIRST_ID 100

static TASKDIALOG_BUTTON *s_messageButtons = NULL;
static int s_messageButtonCount = 0;

void ionMessageBoxAddButton(const char *label) {
    TASKDIALOG_BUTTON *grown = (TASKDIALOG_BUTTON *)realloc(s_messageButtons, (size_t)(s_messageButtonCount + 1) * sizeof(TASKDIALOG_BUTTON));
    if (grown == NULL) abort();
    s_messageButtons = grown;
    wchar_t *w = ionUtf8ToWide(label);
    grown[s_messageButtonCount].nButtonID = ION_MESSAGE_BOX_FIRST_ID + s_messageButtonCount;
    grown[s_messageButtonCount].pszButtonText = w != NULL ? w : _wcsdup(L"");
    s_messageButtonCount++;
}

typedef HRESULT (WINAPI *TaskDialogIndirectFn)(const TASKDIALOGCONFIG *, int *, int *, BOOL *);

int ionMessageBoxRun(const char *title, const char *message, int style) {
    TASKDIALOG_BUTTON *buttons = s_messageButtons;
    int count = s_messageButtonCount;
    s_messageButtons = NULL;
    s_messageButtonCount = 0;

    HMODULE comctl = LoadLibraryW(L"comctl32.dll");
    TaskDialogIndirectFn taskDialog = comctl != NULL ? (TaskDialogIndirectFn)(void *)GetProcAddress(comctl, "TaskDialogIndirect") : NULL;
    int result = ION_MESSAGE_BOX_FAILED;
    if (taskDialog != NULL) {
        wchar_t *wTitle = ionUtf8ToWide(title);
        wchar_t *wMessage = ionUtf8ToWide(message);
        TASKDIALOGCONFIG config = {0};
        config.cbSize = sizeof(config);
        config.hwndParent = s_mainHwnd;
        config.dwFlags = TDF_ALLOW_DIALOG_CANCELLATION | TDF_POSITION_RELATIVE_TO_WINDOW;
        config.pszWindowTitle = wTitle;
        config.pszMainInstruction = wTitle;
        config.pszContent = wMessage;
        config.pszMainIcon = style == ION_MESSAGE_STYLE_CRITICAL ? TD_ERROR_ICON
                           : style == ION_MESSAGE_STYLE_WARNING ? TD_WARNING_ICON
                           : TD_INFORMATION_ICON;
        config.cButtons = (UINT)count;
        config.pButtons = buttons;
        config.nDefaultButton = ION_MESSAGE_BOX_FIRST_ID;
        int pressed = 0;
        HRESULT hr = taskDialog(&config, &pressed, NULL, NULL);
        int index = pressed - ION_MESSAGE_BOX_FIRST_ID;
        if (SUCCEEDED(hr)) result = index >= 0 && index < count ? index : ION_MESSAGE_BOX_DISMISSED;
        free(wTitle);
        free(wMessage);
    }
    if (comctl != NULL) FreeLibrary(comctl);
    for (int i = 0; i < count; i++) free((void *)buttons[i].pszButtonText);
    free(buttons);
    return result;
}
