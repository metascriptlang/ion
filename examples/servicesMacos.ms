// macOS desktop services: focusContent takes keyboard focus back from a webview, announce posts,
// share shows a picker that is then dismissed, and messageBox returns the pressed button's index
// or -1 when aborted. Each is driven and read back through AppKit (servicesMacos.m).

import { focusContent, focusWebview, closeWindow, runLoop, announce, share, messageBox, MessageStyle } from "../src/index";
import { openPage } from "./content/page";
import { exit } from "std/process";

when (macos) {
	@compile("./servicesMacos.m", "-fobjc-arc");
	@passL("-framework WebKit");
}
@include("./servicesMacos.h");

extern function svActivate(): void;
extern function svWebviewHasFocus(): int32;
extern function svFirstResponderClass(): cstring;
extern function svDismissShareWithin(ms: int32): void;
extern function svShareWindowsSeen(): cstring;
extern function svShareWindowsLeft(): int32;
extern function svAnswerAlertAfter(ms: int32, title: cstring): void;
extern function svAlertSeen(): cstring;

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
		console.log("servicesMacos: no window");
		return 1;
	}
	setTimeout((): void => {
		svActivate();
		focusWebview(page.webview);
	}, 500);
	setTimeout((): void => {
		check(`focusWebview gave the webview the keys (${(svFirstResponderClass() as string)})`, svWebviewHasFocus() === (1 as int32));
		focusContent(page.window);
		check(`focusContent took them back to the content host (${(svFirstResponderClass() as string)})`, svWebviewHasFocus() === (0 as int32));

		const posted = announce("Ion services probe");
		check(`announce posted on the key window (${said(posted)})`, posted.ok);

		svDismissShareWithin(3000 as int32);
		const shared = share("Ion", "hello from Ion", "https://example.com");
		check(`share showed the picker (${said(shared)})`, shared.ok);
		check("share refuses an empty text and url", !share("Ion", "", "").ok);
	}, 1500);
	setTimeout((): void => {
		check(`the share picker appeared (${(svShareWindowsSeen() as string)})`, (svShareWindowsSeen() as string) !== "");
		check(`and was dismissed (${svShareWindowsLeft()} windows left)`, svShareWindowsLeft() === (0 as int32));

		svAnswerAlertAfter(500 as int32, "Delete");
		const pressed = messageBox("Ion services", "Delete the probe file?", ["Keep", "Delete", "Cancel"], MessageStyle.Critical);
		check(`messageBox returned the pressed 'Delete' as 1 (${index(pressed)}, seen ${(svAlertSeen() as string)})`,
			pressed.ok && pressed.value === (1 as int32));
		check(`the alert was critical (2) with the three labels in order (${(svAlertSeen() as string)})`, (svAlertSeen() as string) === "2:Keep|Delete|Cancel");

		svAnswerAlertAfter(500 as int32, "");
		const aborted = messageBox("Ion services", "Abort me", [], MessageStyle.Info);
		check(`messageBox closed without a button returned -1 (${index(aborted)}, seen ${(svAlertSeen() as string)})`,
			aborted.ok && aborted.value === (-1 as int32));
		check(`no labels gave one OK button, informational (1) (${(svAlertSeen() as string)})`, (svAlertSeen() as string) === "1:OK");
		closeWindow(page.window);
	}, 5000);
	runLoop();
	console.log(`servicesMacos: ${failures === 0 ? "PASS" : "FAIL"} (${failures} failed)`);
	return failures === 0 ? 0 : 1;
}

exit(main());
