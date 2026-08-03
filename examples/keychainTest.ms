// Standalone test for ion's keychain wrapper. Exercises set → get → delete
// → get to verify round-trip storage + removal under the user's session
// keychain (GNOME Keyring / KWallet via libsecret on Linux, Security.framework
// on macOS, stub on Windows).
//
// Usage:
//   bun ~/metascript/recompiler/bun/run.ts build examples/keychainTest.ms -f
//   ./out/debug/keychainTest
//
// Expected output:
//   set ok=true
//   get value="hello-from-ion"
//   delete ok=true
//   get-after-delete value="" (length=0)

// Import via ../src/index — this pulls ipc.ms into the build graph so its
// @compile/@passC/@passL directives (which own the platform-specific build
// recipe) actually fire. Importing from ../src/keychain alone skips ipc.ms
// → linker can't find ionKeychainDelete because keychain.c never compiles.
import { setSecret, getSecret, deleteSecret } from "../src/index";

function main(): int32 {
	const svc = "io.ion.test";
	const acc = "demo-account";
	const val = "hello-from-ion";

	const setOk = setSecret(svc, acc, val);
	console.log(`set ok=${setOk}`);

	const got = getSecret(svc, acc);
	console.log(`get value="${got}"`);

	const delOk = deleteSecret(svc, acc);
	console.log(`delete ok=${delOk}`);

	const after = getSecret(svc, acc);
	console.log(`get-after-delete value="${after}" (length=${after.length})`);

	return 0 as int32;
}
