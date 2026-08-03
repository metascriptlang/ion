// Ion Windows — UTF-8 ↔ UTF-16 conversion helpers.
//
// Win32 APIs come in two flavors:
//   - "A" suffix: ANSI / current code page — lossy for non-Latin text.
//   - "W" suffix: UTF-16 — the only safe choice for arbitrary text.
//
// Ion's public C contract is UTF-8 (matches MS string encoding); platform
// code converts at the boundary. These helpers centralize that conversion
// so window/webview/IPC/dialog code never reinvents the wheel.

#ifndef ION_WINDOWS_UTF8_H
#define ION_WINDOWS_UTF8_H

#include <wchar.h>

#ifdef __cplusplus
extern "C" {
#endif

// UTF-8 → UTF-16. Caller frees the returned buffer with free().
// Returns NULL on allocation failure or invalid input. Passing NULL is safe
// (returns NULL).
wchar_t *ionUtf8ToWide(const char *utf8);

// UTF-16 → UTF-8. Writes into caller-provided buffer; returns 1 on success,
// 0 on failure (output truncated or conversion error). Output is always
// NUL-terminated on success.
int ionWideToUtf8(const wchar_t *wide, char *out, int outCapacity);

#ifdef __cplusplus
}
#endif

#endif
