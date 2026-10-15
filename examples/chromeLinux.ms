// Linux chrome check: tray, notification and file dialog once each, on a window.
// The last step is Ion's fileOpen, which blocks until the dialog answers and has no cancel
// hook: run it under `timeout 15` and read the output, the dialog needs a person or the kill.
// Before it, the same GtkFileDialog is opened with a GCancellable cancelled after one second,
// which shows whether the dialog path returns cleanly.
// Run in WSL: msc build examples/chromeLinux.ms && timeout 15 out/debug/chromeLinux

import {
	createWindow, defaultOptions, windowRoot, fileOpen, installTray, notify, Window,
} from "../src/index";
import { exit } from "std/process";

when (linux) {
	@compile("./chromeLinux.c");
}
@include("./chromeLinux.h");

extern function chromeOpenAndCancel(root: Ptr<void>): void;
extern function chromeLogDialogToplevels(root: Ptr<void>): void;
extern function chromeBusHasOwner(name: cstring): int32;

function main(): int32 {
	const created = createWindow("main", defaultOptions("Ion chrome", 480 as int32, 300 as int32));
	if (created === null) {
		console.log("chromeLinux: no window");
		return 1;
	}
	const win: Window = created;
	console.log(`bus StatusNotifierWatcher owner: ${chromeBusHasOwner("org.kde.StatusNotifierWatcher")}`);
	console.log(`bus Notifications owner: ${chromeBusHasOwner("org.freedesktop.Notifications")}`);

	installTray("Ion chrome");
	console.log("tray: installTray returned");
	notify("Ion chrome", "notification check", "chrome-check");
	console.log("notify: notify returned");

	chromeOpenAndCancel(windowRoot(win));
	console.log("dialog: Ion fileOpen, waiting for an answer");
	chromeLogDialogToplevels(windowRoot(win));
	const picked = fileOpen(win);
	console.log(`dialog: fileOpen returned '${picked}'`);
	return 0;
}

exit(main());
