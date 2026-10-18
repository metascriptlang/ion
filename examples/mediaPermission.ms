// Microphone or camera permission: check, request, check again.
//
// Usage:
//   msc build examples/mediaPermission.ms
//   out/debug/mediaPermission.exe [camera]
// On macOS run it as a bundle (scripts/make-app.sh) through `open`, with `--args camera`.
import { microphoneAccess, requestMicrophoneAccess, cameraAccess, requestCameraAccess, MediaAccess } from "../src/permission";
import { argv, exit } from "std/process";

function show(label: string, r: Result<MediaAccess, string>): void {
	if (r.ok) {
		console.log(`${label}: status=${r.value.status} canAskAgain=${r.value.canAskAgain}`);
	} else {
		console.log(`${label}: error=${r.error}`);
	}
}

async function main(): Promise<int32> {
	if (argv.length > 1 && argv[1] === "camera") {
		show("camera check", cameraAccess());
		show("camera request", await requestCameraAccess());
		show("camera check after request", cameraAccess());
		return 0;
	}
	show("check", microphoneAccess());
	show("request", await requestMicrophoneAccess());
	show("check after request", microphoneAccess());
	return 0;
}

exit(await main());
