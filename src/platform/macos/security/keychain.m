// Ion macOS — Keychain wrapper.
//
// Thin shim over Apple's Security framework SecItem* APIs. Stores UTF-8
// strings indexed by (service, account) — session tokens, API keys, any
// secret a consumer wants encrypted at rest under macOS login.
//
// Item shape:
//   class        = kSecClassGenericPassword
//   service      = caller-supplied (e.g. bundle ID)
//   account      = caller-supplied (e.g. "session")
//   accessible   = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
//                  (readable after first login post-boot; never iCloud-sync)
//
// Returns 1 on success, 0 on failure. OSStatus error codes are swallowed —
// the caller's fallback path (file storage) handles the miss.

#import "../../bridge.h"
#import "../internal.h"
#import <Foundation/Foundation.h>
#import <Security/Security.h>

static NSMutableDictionary *baseQuery(const char *service, const char *account) {
    return [@{
        (__bridge id)kSecClass:       (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: @(service),
        (__bridge id)kSecAttrAccount: @(account),
    } mutableCopy];
}

int ionKeychainSet(const char *service, const char *account, const char *value) {
    if (!service || !account || !value) return 0;
    NSMutableDictionary *q = baseQuery(service, account);
    NSData *data = [@(value) dataUsingEncoding:NSUTF8StringEncoding];

    // Update if present, else add. SecItemAdd alone returns errSecDuplicateItem
    // on collision — the two-step is the documented Apple pattern.
    OSStatus s = SecItemUpdate((__bridge CFDictionaryRef)q,
                               (__bridge CFDictionaryRef)@{ (__bridge id)kSecValueData: data });
    if (s == errSecSuccess) return 1;
    if (s != errSecItemNotFound) return 0;

    q[(__bridge id)kSecValueData]      = data;
    q[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
    return SecItemAdd((__bridge CFDictionaryRef)q, NULL) == errSecSuccess ? 1 : 0;
}

msString ionKeychainGet(const char *service, const char *account) {
    if (!service || !account) return MS_EMPTY_STRING;

    NSMutableDictionary *q = baseQuery(service, account);
    q[(__bridge id)kSecReturnData]  = @YES;
    q[(__bridge id)kSecMatchLimit]  = (__bridge id)kSecMatchLimitOne;

    CFTypeRef result = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)q, &result) != errSecSuccess) {
        return MS_EMPTY_STRING;
    }
    NSData *data = (__bridge_transfer NSData *)result;
    NSString *value = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return nsStringToMs(value);
}

int ionKeychainDelete(const char *service, const char *account) {
    if (!service || !account) return 0;
    OSStatus s = SecItemDelete((__bridge CFDictionaryRef)baseQuery(service, account));
    // errSecItemNotFound = "already gone" — caller's intent ("ensure absent") satisfied.
    return (s == errSecSuccess || s == errSecItemNotFound) ? 1 : 0;
}
