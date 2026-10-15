// Microphone permission: check, request, check again.
//
// Usage:
//   msc build examples/micPermission.ms
//   out/debug/micPermission.exe
import { microphoneAccess, requestMicrophoneAccess, MicAccess } from "../src/permission";
import { exit } from "std/process";

function show(label: string, r: Result<MicAccess, string>): void {
	if (r.ok) {
		console.log(`${label}: status=${r.value.status} canAskAgain=${r.value.canAskAgain}`);
	} else {
		console.log(`${label}: error=${r.error}`);
	}
}

async function main(): Promise<int32> {
	show("check", microphoneAccess());
	show("request", await requestMicrophoneAccess());
	show("check after request", microphoneAccess());
	return 0;
}

exit(await main());
