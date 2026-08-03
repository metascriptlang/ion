// MIME type lookup from file extension. Plain C, no dependencies.
// Used by ion's custom-protocol handler (protoreg.c) to set Content-Type
// when serving bundled assets through ion:// / asset:// / custom schemes.
//
// Returned string is a static string literal — caller must NOT free.

#ifndef ION_COMMON_MIME_H
#define ION_COMMON_MIME_H

#ifdef __cplusplus
extern "C" {
#endif

// Look up MIME type for a given file path. Examines the extension after the
// last `.`. Returns `application/octet-stream` for unknown / extensionless.
// `path` may be NULL → returns the octet-stream default.
const char *ionMimeForPath(const char *path);

#ifdef __cplusplus
}
#endif

#endif
