// Microphone and camera permission: read the OS state, or ask the user when the OS can.
//
// Neither call answers granted unless the OS says so. Where the OS has no prompt for this kind
// of app (Windows desktop), request returns the current state and `canAskAgain` is false.

// Build directives live here: an app that only asks for access must not pull in the window host.
when (windows) {
	@compile("./platform/windows/security/mediaAccess.c");
}

when (macos) {
	@compile("./platform/macos/security/mediaAccess.m", "-fobjc-arc");
	@passL("-framework Foundation");
	@passL("-framework AVFoundation");
}

when (linux) {
	@compile("./platform/linux/security/mediaAccess.c");
}

import { ionMediaAccess, ionMediaRequest, ionMediaErrorName } from "./platform/bridge.h";
import { MediaAccess, mediaAccessFromCode } from "./permissionCode";

export { MediaAccess } from "./permissionCode";

const microphoneKind: int32 = 0 as int32;
const cameraKind: int32 = 1 as int32;

function decoded(api: string, code: int32): Result<MediaAccess, string> {
	if (code < 0) { return Result.err(api + ": " + ionMediaErrorName(code) as string); }
	return mediaAccessFromCode(code);
}

export function microphoneAccess(): Result<MediaAccess, string> {
	return decoded("microphoneAccess", ionMediaAccess(microphoneKind));
}

// Prompts on macOS; the user's answer arrives once. The native call blocks, so it runs on a spawn.
export async function requestMicrophoneAccess(): Promise<Result<MediaAccess, string>> {
	const code = await spawn(() => ionMediaRequest(microphoneKind));
	return decoded("requestMicrophoneAccess", code);
}

export function cameraAccess(): Result<MediaAccess, string> {
	return decoded("cameraAccess", ionMediaAccess(cameraKind));
}

// Prompts on macOS, as requestMicrophoneAccess does.
export async function requestCameraAccess(): Promise<Result<MediaAccess, string>> {
	const code = await spawn(() => ionMediaRequest(cameraKind));
	return decoded("requestCameraAccess", code);
}
