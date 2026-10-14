// Ion Windows — text clipboard (CF_UNICODETEXT).

#include "../state.h"
#include "../utf8.h"
#include "../../bridge.h"
#include "../../common/strconv.h"

#include <stdlib.h>
#include <string.h>
#include <wchar.h>

// Another process can hold the clipboard open for a few milliseconds.
static int openClipboard(void) {
    for (int attempt = 0; attempt < 10; attempt++) {
        if (OpenClipboard(s_mainHwnd)) return 1;
        Sleep(10);
    }
    return 0;
}

msString ionClipboardRead(void) {
    if (!openClipboard()) return MS_EMPTY_STRING;
    msString out = MS_EMPTY_STRING;
    HANDLE data = GetClipboardData(CF_UNICODETEXT);
    if (data != NULL) {
        const wchar_t *wide = (const wchar_t *)GlobalLock(data);
        if (wide != NULL) {
            int needed = WideCharToMultiByte(CP_UTF8, 0, wide, -1, NULL, 0, NULL, NULL);
            char *utf8 = needed > 1 ? (char *)malloc((size_t)needed) : NULL;
            if (utf8 != NULL && WideCharToMultiByte(CP_UTF8, 0, wide, -1, utf8, needed, NULL, NULL) > 0) {
                out = cStringToMs(utf8);
            }
            free(utf8);
            GlobalUnlock(data);
        }
    }
    CloseClipboard();
    return out;
}

int ionClipboardWrite(const char *text) {
    wchar_t *wide = ionUtf8ToWide(text != NULL ? text : "");
    if (wide == NULL) return 0;
    size_t bytes = (wcslen(wide) + 1) * sizeof(wchar_t);
    HGLOBAL mem = GlobalAlloc(GMEM_MOVEABLE, bytes);
    void *dst = mem != NULL ? GlobalLock(mem) : NULL;
    if (dst == NULL) {
        if (mem != NULL) GlobalFree(mem);
        free(wide);
        return 0;
    }
    memcpy(dst, wide, bytes);
    GlobalUnlock(mem);
    free(wide);
    if (!openClipboard()) {
        GlobalFree(mem);
        return 0;
    }
    EmptyClipboard();
    // The system owns `mem` once SetClipboardData succeeds.
    int ok = SetClipboardData(CF_UNICODETEXT, mem) != NULL;
    if (!ok) GlobalFree(mem);
    CloseClipboard();
    return ok;
}
