// Ion Windows — open a URL via ShellExecuteW ("open" verb). UTF-8 in,
// UTF-16 out for the wide shell API.

#include <windows.h>
#include <shellapi.h>
#include <stdlib.h>

void ionOpenExternal(const char *url) {
    if (url == NULL || url[0] == '\0') return;
    int n = MultiByteToWideChar(CP_UTF8, 0, url, -1, NULL, 0);
    if (n <= 0) return;
    wchar_t *w = (wchar_t *)malloc((size_t)n * sizeof(wchar_t));
    if (w == NULL) return;
    MultiByteToWideChar(CP_UTF8, 0, url, -1, w, n);
    ShellExecuteW(NULL, L"open", w, NULL, NULL, SW_SHOWNORMAL);
    free(w);
}
