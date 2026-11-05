// A native library's UI Automation hook on Windows (ionWindowSetAutomation, for Neon's niwGetObject):
// without it WM_GETOBJECT UiaRootObjectId reaches the webview host's provider; with it the hook's
// LRESULT comes back, other object ids it declines go on to the window proc, removing it restores the
// host, and the hook's disconnect runs when the window is destroyed. Run it in the console session.

import { closeWindow, runLoop } from "../src/index";
import { openPage } from "./content/page";
import { exit } from "std/process";

when (windows) {
	@compile("./windowProbeWindows.c");
}
@include("./windowProbeWindows.h");

extern function wpInstallAutomation(window: int32): void;
extern function wpRemoveAutomation(window: int32): void;
extern function wpGetObject(window: int32, objectId: int32): int32;
extern function wpHookCalls(): int32;
extern function wpHookSaw(window: int32, objectId: int32): int32;
extern function wpDisconnects(): int32;
extern function wpRemember(window: int32): void;
extern function wpDisconnectedRemembered(): int32;

const UIA_ROOT: int32 = -25 as int32;
const OBJID_CLIENT: int32 = -4 as int32;

let failures = 0;

function check(name: string, ok: boolean): void {
	console.log(`${ok ? "PASS" : "FAIL"} ${name}`);
	if (!ok) failures += 1;
}

function main(): int32 {
	const page = openPage("Ion automation", 480 as int32, 320 as int32, "page", "data:text/html,<button>hi</button>");
	if (page === null) {
		console.log("automationWindows: no window");
		return 1;
	}
	const id = page.window.id;
	setTimeout((): void => {
		const host = wpGetObject(id, UIA_ROOT);
		check(`without a hook UiaRootObjectId gets the webview host's provider (${host}, hook calls ${wpHookCalls()})`,
			host === (2 as int32) && wpHookCalls() === (0 as int32));

		wpInstallAutomation(id);
		const hooked = wpGetObject(id, UIA_ROOT);
		check(`with a hook its LRESULT comes back (${hooked})`, hooked === (1 as int32));
		check(`the hook saw the window's HWND and UiaRootObjectId (calls ${wpHookCalls()})`,
			wpHookCalls() === (1 as int32) && wpHookSaw(id, UIA_ROOT) === (1 as int32));

		const client = wpGetObject(id, OBJID_CLIENT);
		check(`an object id the hook declines goes on to the window proc (${client}, calls ${wpHookCalls()})`,
			client !== (1 as int32) && wpHookCalls() === (2 as int32) && wpHookSaw(id, OBJID_CLIENT) === (1 as int32));

		wpRemoveAutomation(id);
		const restored = wpGetObject(id, UIA_ROOT);
		check(`a removed hook leaves the host's provider (${restored}, calls ${wpHookCalls()})`,
			restored === (2 as int32) && wpHookCalls() === (2 as int32));

		wpInstallAutomation(id);
		wpRemember(id);
		closeWindow(page.window);
	}, 1500);
	runLoop();
	check(`the hook's disconnect ran once for the destroyed window (${wpDisconnects()})`,
		wpDisconnects() === (1 as int32) && wpDisconnectedRemembered() === (1 as int32));
	console.log(failures === 0 ? "automationWindows: all PASS" : `automationWindows: ${failures} FAIL`);
	return failures === 0 ? 0 : 1;
}

exit(main());
