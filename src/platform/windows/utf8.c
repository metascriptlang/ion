// Ion Windows — UTF-8 ↔ UTF-16 conversion (see utf8.h).

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include "utf8.h"

#include <stdlib.h>

wchar_t *ionUtf8ToWide(const char *utf8) {
    if (utf8 == NULL) return NULL;
    int needed = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, NULL, 0);
    if (needed <= 0) return NULL;
    wchar_t *buf = (wchar_t *)malloc((size_t)needed * sizeof(wchar_t));
    if (buf == NULL) return NULL;
    if (MultiByteToWideChar(CP_UTF8, 0, utf8, -1, buf, needed) <= 0) {
        free(buf);
        return NULL;
    }
    return buf;
}

int ionWideToUtf8(const wchar_t *wide, char *out, int outCapacity) {
    if (wide == NULL || out == NULL || outCapacity <= 0) return 0;
    int written = WideCharToMultiByte(CP_UTF8, 0, wide, -1,
                                      out, outCapacity, NULL, NULL);
    return written > 0 ? 1 : 0;
}
