// Windows desktop services: focusContent takes keyboard focus back from a webview, announce raises
// a UIA notification, messageBox shows a task dialog (Common Controls v6 from Ion's manifest) that the
// probe answers by button id and then closes, and share opens the share UI (left for a screenshot,
// closed with the window). Run it in the console session.

import { focusContent, focusWebview, closeWindow, runLoop, announce, share, messageBox, MessageStyle } from "../src/index";
import { openPage } from "./content/page";
import { exit } from "std/process";

when (windows) {
	@compile("./servicesWindows.c");
}
@include("./servicesWindows.h");

extern function swFocus(window: int32): int32;
extern function swActive(window: int32): int32;
extern function swManifestNamesCommonControls(): int32;
extern function swTaskDialogComctlMajor(): int32;
extern function swAnswerDialogAfter(ms: int32, id: int32): void;
extern function swDialogSeen(): cstring;

let failures = 0;

function check(what: string, ok: boolean): void {
	if (!ok) failures += 1;
	console.log(`${ok ? "PASS" : "FAIL"} ${what}`);
}

function said(r: Result<void, string>): string { return r.ok ? "ok" : r.error; }
function index(r: Result<int32, string>): string { return r.ok ? `${r.value}` : r.error; }

function main(): int32 {
	const page = openPage("Ion services", 480 as int32, 320 as int32, "page", "data:text/html,<input autofocus>");
	if (page === null) {
		console.log("servicesWindows: no window");
		return 1;
	}
	const id = page.window.id;
	setTimeout((): void => { focusWebview(page.webview); }, 1500);
	setTimeout((): void => {
		check(`focusWebview put the keys in a child window (${swFocus(id)})`, swFocus(id) === (2 as int32));
		focusContent(page.window);
		check(`focusContent took them back to the window (${swFocus(id)})`, swFocus(id) === (1 as int32));
		console.log(`INFO window active: ${swActive(id)}`);

		const posted = announce("Ion services probe");
		check(`announce raised a UIA notification (${said(posted)})`, posted.ok);

		check("the exe's manifest names Common Controls", swManifestNamesCommonControls() === (1 as int32));
		check(`TaskDialogIndirect resolves in comctl32 v6 (${swTaskDialogComctlMajor()})`, swTaskDialogComctlMajor() === (6 as int32));

		swAnswerDialogAfter(300 as int32, 101 as int32);
		const pressed = messageBox("Ion services", "Delete the probe file?", ["Keep", "Delete", "Cancel"], MessageStyle.Critical);
		check(`messageBox returned the pressed 'Delete' as 1 (${index(pressed)}, seen ${(swDialogSeen() as string)})`,
			pressed.ok && pressed.value === (1 as int32));
		check(`it was a task dialog titled 'Ion services' (${(swDialogSeen() as string)})`, (swDialogSeen() as string) === "#32770:Ion services");

		swAnswerDialogAfter(300 as int32, 0 as int32);
		const aborted = messageBox("Ion services", "Abort me", [], MessageStyle.Info);
		check(`messageBox closed without a button returned -1 (${index(aborted)}, seen ${(swDialogSeen() as string)})`,
			aborted.ok && aborted.value === (-1 as int32));

		const shared = share("Ion", "hello from Ion", "https://example.com");
		check(`share opened the share UI (${said(shared)})`, shared.ok);
		console.log("CAPTURE share UI");
	}, 2500);
	setTimeout((): void => { closeWindow(page.window); }, 7000);
	runLoop();
	console.log(`servicesWindows: ${failures === 0 ? "PASS" : "FAIL"} (${failures} failed)`);
	return failures === 0 ? 0 : 1;
}

exit(main());
