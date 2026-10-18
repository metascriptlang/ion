// What a microphone or camera state from the bridge means. Pure MetaScript so it is testable without an OS.

export struct MediaAccess {
	status: string;
	canAskAgain: boolean;
}

const stateMask = 0xff;
const canAskFlag = 0x100;

// Decodes ionMediaAccess / ionMediaRequest: a state OR-ed with the can-ask flag. A negative code is
// the caller's to name, so it never reaches here.
export function mediaAccessFromCode(code: int32): Result<MediaAccess, string> {
	const state = code & stateMask;
	const canAskAgain = (code & canAskFlag) !== 0;
	if (state === 0) { return Result.ok({ status: "granted", canAskAgain }); }
	if (state === 1) { return Result.ok({ status: "denied", canAskAgain }); }
	if (state === 2) { return Result.ok({ status: "undetermined", canAskAgain }); }
	return Result.err("unknown media access state " + state.toString());
}
