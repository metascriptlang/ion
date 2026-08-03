// Ion Windows — native file open dialog via IFileOpenDialog (COM).
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
#include "../../bridge.h"
#include "../../common/strconv.h"

// COBJMACROS lets us call COM methods via `IFoo_Method(pInstance, ...)`
// helper macros, which keeps the C-style vtable invocations readable.
#define COBJMACROS
#include <shobjidl.h>
#include <objbase.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Cached path from the most recent successful pick. Valid until the next
// ionFileOpen call (matches mac's s_lastFilePath lifetime contract).
static char s_lastFilePath[1024] = {0};

msString ionFileOpen(void) {
    s_lastFilePath[0] = '\0';

    HRESULT hrInit = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    if (FAILED(hrInit) && hrInit != RPC_E_CHANGED_MODE) return MS_EMPTY_STRING;

    IFileOpenDialog *pDialog = NULL;
    HRESULT hr = CoCreateInstance(
        &CLSID_FileOpenDialog, NULL, CLSCTX_INPROC_SERVER,
        &IID_IFileOpenDialog, (void **)&pDialog);
    if (FAILED(hr) || pDialog == NULL) return MS_EMPTY_STRING;

    // Show modal. s_mainHwnd as parent so the dialog activates on top of
    // our window + blocks input to it (standard parent-child modal flow).
    hr = IFileOpenDialog_Show(pDialog, s_mainHwnd);
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
