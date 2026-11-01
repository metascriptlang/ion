// Ion Windows — the app's identifier: the executable's name without ".exe".

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <string.h>

#include "../utf8.h"
#include "../../bridge.h"

msString ionAppIdentifier(void) {
    wchar_t path[MAX_PATH];
    DWORD n = GetModuleFileNameW(NULL, path, MAX_PATH);
    if (n == 0 || n == MAX_PATH) return MS_EMPTY_STRING;
    wchar_t *name = wcsrchr(path, L'\\');
    name = name ? name + 1 : path;
    wchar_t *dot = wcsrchr(name, L'.');
    if (dot && _wcsicmp(dot, L".exe") == 0) *dot = L'\0';
    char utf8[MAX_PATH * 4];
    if (!ionWideToUtf8(name, utf8, (int)sizeof(utf8))) return MS_EMPTY_STRING;
    return msStringFromCStr(utf8);
}
