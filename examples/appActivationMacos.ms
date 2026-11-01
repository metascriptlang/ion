// App activation messages: the app comes to the front, another app takes it, the app hides and
// unhides; `listen` receives app.active, app.inactive, app.hidden and app.shown in that order.

import { createWindow, defaultOptions, closeWindow, runLoop, listen } from "../src/index";
import { exit } from "std/process";

when (macos) {
	@compile("./appActivationMacos.m", "-fobjc-arc");
}
@include("./appActivationMacos.h");

extern function aaActivateSelf(): void;
extern function aaActivateFinder(): void;
extern function aaHide(): void;
extern function aaUnhide(): void;

const seen: string[] = [];

function main(): int32 {
	const win = createWindow("main", defaultOptions("Ion activation", 320 as int32, 200 as int32));
	if (win === null) {
		console.log("appActivationMacos: no window");
		return 1;
	}
	listen((name: string, payload: string): void => {
		if (name.startsWith("app.")) seen.push(name);
	});
	setTimeout((): void => { aaActivateSelf(); }, 300);
	setTimeout((): void => { aaActivateFinder(); }, 1000);
	setTimeout((): void => { aaActivateSelf(); }, 1700);
	setTimeout((): void => { aaHide(); }, 2400);
	setTimeout((): void => { aaUnhide(); }, 3100);
	setTimeout((): void => { closeWindow(win); }, 3800);
	runLoop();
	const order = seen.join(",");
	console.log(`appActivationMacos: ${order}`);
	const want = ["app.active", "app.inactive", "app.active", "app.hidden", "app.shown"];
	let at = 0;
	for (const name of seen) if (at < want.length && name == want[at]) at++;
	console.log(`appActivationMacos: ${at == want.length ? "PASS" : "FAIL"} active, inactive, active, hidden, shown in order`);
	return at == want.length ? 0 : 1;
}

exit(main());
