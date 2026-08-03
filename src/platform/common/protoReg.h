// Custom URI scheme registry — cross-platform store of (scheme, baseDir) pairs
// + asset:// scope allowlist. Platform impls (macOS WKURLSchemeHandler, Windows
// WebView2 WebResourceRequested) call ionProtoLookup() to serve a request.
//
// Registry is mutable until ionProtoFreeze() is called (at ionOpen() time),
// then read-only. Reads after freeze are thread-safe by construction — the
// platform callback (WebKit main thread / WebView2 COM thread) reads immutable
// memory.

#ifndef ION_COMMON_PROTOREG_H
#define ION_COMMON_PROTOREG_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Registration outcome / lookup status — distinguish "no handler for this
// scheme" (404 → platform falls back to native) vs "handler matched but no
// such file" (404 → return 404 body).
typedef enum {
    IonProtoOk         = 0,  // Found, bytes returned via out params
    IonProtoNotFound   = 1,  // Scheme registered, but file missing → 404
    IonProtoForbidden  = 2,  // Path traversal / outside asset scope → 403
    IonProtoNoScheme   = 3,  // Scheme not registered → platform decides
    IonProtoFrozen     = 4,  // Tried to register after freeze
    IonProtoDuplicate  = 5,  // Scheme already registered
    IonProtoInvalid    = 6,  // Bad input (empty scheme, missing baseDir)
} IonProtoStatus;

// Register `<scheme>://localhost/<path>` → `<baseDir>/<path>`. Must be called
// BEFORE ionProtoFreeze(). Returns IonProtoOk on success.
IonProtoStatus ionProtoRegister(const char *scheme, const char *baseDir);

// Register the asset:// scheme with allowlist of root paths. `roots` is a
// newline-separated list of absolute paths. Must be called BEFORE freeze.
IonProtoStatus ionProtoRegisterAsset(const char *roots);

// Freeze the registry — subsequent register calls fail with IonProtoFrozen.
// Called from ionOpen().
void ionProtoFreeze(void);

// True after freeze. Used by bridge wrappers to log a clear "register too
// late" warning.
int ionProtoIsFrozen(void);

// Count of registered schemes. Used by platform impls to iterate.
int ionProtoSchemeCount(void);
// Scheme name at index i. Caller must NOT free. NULL if out of range.
const char *ionProtoSchemeAt(int i);

// Lookup: serve `<scheme>://localhost/<rawPath>`.
//
// On IonProtoOk:
//   *outBody   — file contents (caller frees with free())
//   *outLen    — length
//   *outMime   — static string literal (do NOT free)
//   *outStatus — 200
//
// On IonProtoNotFound / IonProtoForbidden:
//   *outBody   — NULL
//   *outLen    — 0
//   *outMime   — "text/plain; charset=utf-8"
//   *outStatus — 404 or 403
//
// On IonProtoNoScheme: all out params untouched.
IonProtoStatus ionProtoLookup(
    const char *scheme,
    const char *rawPath,
    unsigned char **outBody,
    size_t *outLen,
    const char **outMime,
    int *outStatus
);

// Reset registry — test-only entry point.
void ionProtoResetForTests(void);

#ifdef __cplusplus
}
#endif

#endif
