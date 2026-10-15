// Microphone permission: read the OS state, or ask the user when the OS can.
//
// Neither call answers granted unless the OS says so. Where the OS has no prompt for this kind
// of app (Windows desktop), request returns the current state and `canAskAgain` is false.

// Build directives live here: an app that only asks for access must not pull in the window host.
when (windows) {
	@compile("./platform/windows/security/microphone.c");
}

when (macos) {
	@compile("./platform/macos/security/microphone.m", "-fobjc-arc");
	@passL("-framework Foundation");
	@passL("-framework AVFoundation");
}

when (linux) {
	@compile("./platform/linux/security/microphone.c");
}

import { ionMicAccess, ionMicRequest, ionMicErrorName } from "./platform/bridge.h";
import { MicAccess, micAccessFromCode } from "./permissionCode";

export { MicAccess } from "./permissionCode";

function decoded(api: string, code: int32): Result<MicAccess, string> {
	if (code < 0) { return Result.err(api + ": " + ionMicErrorName(code)); }
	return micAccessFromCode(code);
}

export function microphoneAccess(): Result<MicAccess, string> {
	return decoded("microphoneAccess", ionMicAccess());
}

// Prompts on macOS; the user's answer arrives once. The native call blocks, so it runs on a spawn.
export async function requestMicrophoneAccess(): Promise<Result<MicAccess, string>> {
	const code = await spawn(() => ionMicRequest());
	return decoded("requestMicrophoneAccess", code);
}
