// Ion Linux — Keychain wrapper via libsecret (D-Bus Secret Service).
//
// Speaks `org.freedesktop.secrets` — the cross-DE secrets daemon protocol.
// Concrete daemon depends on user's session: GNOME Keyring on GNOME, KWallet
// (with the secrets proxy) on KDE, gnome-keyring-daemon on most other DEs.
//
// Item shape:
//   schema name  = "io.ion.Password" (private to ion's stored items)
//   attributes   = (service, account) as STRINGs — same shape as Mac's
//                  (kSecAttrService, kSecAttrAccount) tuple.
//   collection   = SECRET_COLLECTION_DEFAULT (user's primary keyring;
//                  encrypted at rest under login password).
//
// Returns 1 on success, 0 on failure. GErrors swallowed — caller's fallback
// path (file storage) handles the miss.
//
// Flatpak: requires `--talk-name=org.freedesktop.secrets` in finish-args
// so the sandboxed app can reach the host's keyring daemon over DBus.

#include "../../bridge.h"
#include "../../common/strconv.h"

#include <libsecret/secret.h>
#include <glib.h>
#include <string.h>

// Schema identifies the storage "namespace" — items in the keyring carry
// this name + their attributes. Different schemas can share attribute names
// without conflict. Trailing pad fields (reserved1..reserved8) avoid
// missing-initializer warnings under -Wmissing-field-initializers.
static const SecretSchema kIonSchema = {
    "io.ion.Password",
    SECRET_SCHEMA_NONE,
    {
        { "service", SECRET_SCHEMA_ATTRIBUTE_STRING },
        { "account", SECRET_SCHEMA_ATTRIBUTE_STRING },
        { NULL,      0                              },
    },
    /* reserved   */ 0,
    /* reserved1  */ NULL, NULL, NULL, NULL, NULL, NULL, NULL,
};

int ionKeychainSet(const char *service, const char *account, const char *value) {
    if (service == NULL || account == NULL || value == NULL) return 0;

    GError *err = NULL;
    // store_sync upserts: if an item with matching attributes exists, it's
    // overwritten. Label "ion" surfaces in keyring browsers (Seahorse) as a
    // user-readable hint; not used for lookup.
    gboolean ok = secret_password_store_sync(
        &kIonSchema, SECRET_COLLECTION_DEFAULT,
        "ion", value,
        NULL, &err,
        "service", service,
        "account", account,
        NULL);
    if (err != NULL) g_error_free(err);
    return ok ? 1 : 0;
}

msString ionKeychainGet(const char *service, const char *account) {
    if (service == NULL || account == NULL) return MS_EMPTY_STRING;

    GError *err = NULL;
    gchar *pw = secret_password_lookup_sync(
        &kIonSchema, NULL, &err,
        "service", service,
        "account", account,
        NULL);
    if (err != NULL) g_error_free(err);
    if (pw == NULL) return MS_EMPTY_STRING;

    msString out = cStringToMs(pw);
    // secret_password_free zero-fills before releasing — keeps the secret
    // out of freed-heap residue. Don't replace with plain g_free.
    secret_password_free(pw);
    return out;
}

int ionKeychainDelete(const char *service, const char *account) {
    if (service == NULL || account == NULL) return 0;

    GError *err = NULL;
    gboolean ok = secret_password_clear_sync(
        &kIonSchema, NULL, &err,
        "service", service,
        "account", account,
        NULL);
    if (err != NULL) g_error_free(err);
    // libsecret returns FALSE when nothing matched — caller's intent
    // ("ensure absent") is satisfied either way. Match Mac's behavior.
    (void)ok;
    return 1;
}
