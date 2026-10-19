// Single instance is opt-in. Run it twice:
//   singleInstance            both processes open a window and stay alive
//   singleInstance --single   the second prints "secondary: false" and exits; the
//                             primary logs the forwarded deeplink and is raised
// An argument containing `://` is the cold-start URL. Run with stdout redirected
// (GUI subsystem). The primary exits by itself after 10 s.

import {
	createWindow, defaultOptions, commit, listen, runLoop, requestSingleInstance,
} from "../src/index";
import { argv, exit } from "std/process";

function main(): int32 {
	let single = false;
	for (let i = 1; i < argv.length; i++) {
		if (argv[i] === "--single") single = true;
	}
	if (single) {
		const first = requestSingleInstance();
		const again = requestSingleInstance();
		if (first !== again) { console.log("FAIL: second call answered differently"); return 1; }
		if (!first) {
			console.log("secondary: requestSingleInstance false, exiting");
			return 0;
		}
		console.log("primary: requestSingleInstance true");
	}
	const win = createWindow("main", defaultOptions("Ion single instance", 480 as int32, 240 as int32));
	if (win === null) {
		console.log("FAIL: no window");
		return 1;
	}
	commit(win);
	let late = false;
	try {
		requestSingleInstance();
	} catch (e) {
		late = true;
	}
	console.log(late ? "PASS: late requestSingleInstance threw" : "FAIL: late requestSingleInstance returned");
	listen((name: string, payload: string): void => {
		console.log(`message: ${name} ${payload}`);
	});
	setTimeout((): void => { exit(0); }, 10000);
	console.log("running");
	runLoop();
	return 0;
}

exit(main());
