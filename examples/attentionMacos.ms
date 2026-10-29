// Asks for the user's attention from the background: run it, activate another app within 1.5 s,
// and the dock icon bounces until the app is active again (Critical); a beep sounds first.

import { createWindow, defaultOptions, closeWindow, runLoop, requestUserAttention, beep, AttentionCritical, AttentionInformational } from "../src/index";
import { exit } from "std/process";

function main(): int32 {
	const win = createWindow("main", defaultOptions("Ion attention", 320 as int32, 200 as int32));
	if (win === null) {
		console.log("attentionMacos: no window");
		return 1;
	}
	setTimeout((): void => {
		beep();
		requestUserAttention(win, AttentionCritical);
		console.log("attentionMacos: asked (critical)");
	}, 1500);
	setTimeout((): void => {
		requestUserAttention(win, AttentionInformational);
		console.log("attentionMacos: asked (informational)");
	}, 4500);
	setTimeout((): void => { closeWindow(win); }, 6000);
	runLoop();
	return 0;
}

exit(main());
