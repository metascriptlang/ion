// Secure secret store via OS keychain.
//
// macOS: Security.framework SecItem APIs — login keychain (encrypted at rest
//        under login password).
// Linux: libsecret talks to org.freedesktop.secrets — GNOME Keyring / KWallet
//        / gnome-keyring-daemon depending on the user's DE. Flatpak builds
//        need `--talk-name=org.freedesktop.secrets` finish-arg.
// Windows: Credential Manager via CredWriteW / CredReadW / CredDeleteW
//        (advapi32). Values are capped by the blob size limit — see
//        platform/windows/security/keychain.c for the practical ceiling.
//
// Usage:
//   const ok = setSecret("com.example.app", "session", token);
//   const token = getSecret("com.example.app", "session");
//   deleteSecret("com.example.app", "session");
//
// String convention: ionKeychainGet returns msString natively from the C
// side (see platform/bridge.h header note), so this wrapper is a 1:1
// passthrough with no fromC/msStringFromCStr wrapping at the MS site.

import {
	ionKeychainSet,
	ionKeychainGet,
	ionKeychainDelete,
} from "./platform/bridge.h";

export function setSecret(service: string, account: string, value: string): boolean {
	return ionKeychainSet(service, account, value) === 1;
}

export function getSecret(service: string, account: string): string {
	return ionKeychainGet(service, account);
}

export function deleteSecret(service: string, account: string): boolean {
	return ionKeychainDelete(service, account) === 1;
}
