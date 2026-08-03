// Ion Windows — Keychain wrapper via Windows Credential Manager.
//
// CredWriteW / CredReadW / CredDeleteW operate on the per-user vault that
// Credential Manager exposes (Settings → Stored Credentials). Items are
// keyed by TargetName; we encode (service, account) as "service:account"
// so a single TargetName identifies a tuple — same shape as Mac's
// (kSecAttrService, kSecAttrAccount) + Linux libsecret schema attrs.
//
// Item shape:
//   Type        = CRED_TYPE_GENERIC (1)
//   TargetName  = L"<service>:<account>" — primary lookup key
//   UserName    = L"<account>"           — secondary metadata, displayed in UI
//   Persist     = CRED_PERSIST_LOCAL_MACHINE — survives reboot, NOT roamed
//                 (matches Mac's kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
//   CredentialBlob = UTF-8 bytes of value — Win treats blob as opaque,
//                    no automatic encoding conversion.
//
// Blob size cap: Win docs say 512 bytes for v1, 5*512 = 2560 bytes practical;
// we use a 4 KB receive buffer for ionKeychainGet which covers any token or
// API key sized payload. Larger values truncate silently — MyApp secrets
// are tokens / session IDs, not file contents.

#include "../../bridge.h"
#include "../utf8.h"
#include "../internal.h"

#include <wincred.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Convert "service:account" (both UTF-8) to a heap-allocated wide string.
// Caller frees via free(). Returns NULL on failure.
static wchar_t *buildTargetName(const char *service, const char *account) {
    if (service == NULL || account == NULL) return NULL;
    size_t needed = strlen(service) + 1 + strlen(account) + 1;
    char *composed = (char *)malloc(needed);
    if (composed == NULL) return NULL;
    snprintf(composed, needed, "%s:%s", service, account);
    wchar_t *wide = ionUtf8ToWide(composed);
    free(composed);
    return wide;
}

int ionKeychainSet(const char *service, const char *account, const char *value) {
    if (service == NULL || account == NULL || value == NULL) return 0;

    wchar_t *targetName = buildTargetName(service, account);
    if (targetName == NULL) return 0;
    wchar_t *userName = ionUtf8ToWide(account);
    if (userName == NULL) { free(targetName); return 0; }

    CREDENTIALW cred = {0};
    cred.Type               = CRED_TYPE_GENERIC;
    cred.TargetName         = targetName;
    cred.UserName           = userName;
    cred.CredentialBlobSize = (DWORD)strlen(value);
    cred.CredentialBlob     = (LPBYTE)value;  // opaque bytes — Win doesn't transcode
    cred.Persist            = CRED_PERSIST_LOCAL_MACHINE;

    BOOL ok = CredWriteW(&cred, 0);

    free(targetName);
    free(userName);
    return ok ? 1 : 0;
}

msString ionKeychainGet(const char *service, const char *account) {
    if (service == NULL || account == NULL) return MS_EMPTY_STRING;

    wchar_t *targetName = buildTargetName(service, account);
    if (targetName == NULL) return MS_EMPTY_STRING;

    PCREDENTIALW cred = NULL;
    BOOL ok = CredReadW(targetName, CRED_TYPE_GENERIC, 0, &cred);
    free(targetName);
    if (!ok || cred == NULL) return MS_EMPTY_STRING;

    // Copy blob into a null-terminated buffer. Blob is the raw UTF-8 bytes
    // ionKeychainSet wrote; we restore the original C string here.
    char buf[4096];
    DWORD len = cred->CredentialBlobSize;
    if (len >= sizeof(buf)) len = sizeof(buf) - 1;
    memcpy(buf, cred->CredentialBlob, len);
    buf[len] = '\0';

    CredFree(cred);
    return cStringToMs(buf);
}

int ionKeychainDelete(const char *service, const char *account) {
    if (service == NULL || account == NULL) return 0;

    wchar_t *targetName = buildTargetName(service, account);
    if (targetName == NULL) return 0;

    BOOL ok = CredDeleteW(targetName, CRED_TYPE_GENERIC, 0);
    DWORD lastErr = ok ? 0 : GetLastError();
    free(targetName);

    // ERROR_NOT_FOUND = "ensure absent" already satisfied. Match Mac
    // (errSecItemNotFound tolerated) + Linux (libsecret zero-match) semantics.
    if (ok || lastErr == ERROR_NOT_FOUND) return 1;
    return 0;
}
