// macOS chrome check: tray, content protection, openExternal, an external link from the page,
// asset://, the file dialog, notifications and a global hotkey, each read back through AppKit
// (chromeMacos.m). Needs a bundle with the URL scheme `ionchrome`; CHROME_LINK names an http URL
// outside localhost for the link step, CHROME_ASSET_ROOT a directory holding `asset.txt` for the
// asset step. A person answers the notification prompt. With CHROME_PERSON=1 a person also clicks
// the tray item, picks a file, clicks the notification and presses Ctrl+Option+Cmd+H while the app
// is hidden; the lines starting with ACTION say when, and CAPTURE gives the window (0: the screen)
// to screenshot.

import {
	windowRoot, closeWindow, setWindowContentProtected, fileOpen, evalJs, listen, runLoop,
	installTray, notify, openExternal, registerAssetScope, tryRegisterHotkeyKey, unregisterHotkey, HotkeyResult,
	ModCmd, ModAlt, ModCtrl, Webview, Window,
} from "../src/index";
import { openPage } from "./content/page";
import { env, exit } from "std/process";

when (macos) {
	@compile("./chromeMacos.m", "-fobjc-arc");
	@passL("-framework UserNotifications");
}
@include("./chromeMacos.h");

extern function chromeTrayVisible(title: cstring): int32;
extern function chromeTrayClick(title: cstring): int32;
extern function chromeAppActive(): int32;
extern function chromeHideApp(): void;
extern function chromeWindowIsKey(root: Ptr<void>): int32;
extern function chromeWindowNumber(root: Ptr<void>): int32;
extern function chromeSharingType(root: Ptr<void>): int32;
extern function chromeNotifyQuery(): void;
extern function chromeNotifyAuth(): int32;
extern function chromeNotifyDelivered(id: cstring): int32;
extern function chromeCancelModalAfter(ms: int32): void;
extern function chromeCancelledOpenPanel(): int32;

const TRAY = "Ion";
const DEEP_LINK = "ionchrome://probe/open";
const AUTHORIZED: int32 = 2 as int32;
const HOTKEY_ID: int32 = 7 as int32;
const LAST_STEP = 10;

let failures = 0;
let stepName = "";
let messages = "";
let picked = "";
let pickedMs: number = 0;
let hotkey = HotkeyResult.Ok;
let notifyAuth: int32 = -1 as int32;
let activeAtHotkey: int32 = -1 as int32;
let assetInside = "";
let assetOutside = "";
const link = env.get("CHROME_LINK");
const person = env.get("CHROME_PERSON") === "1";
const assetRoot = env.get("CHROME_ASSET_ROOT");

function check(what: string, ok: boolean): void {
	if (!ok) failures += 1;
	console.log(`${ok ? "PASS" : "FAIL"} [${stepName}] ${what}`);
}

function waitFor(done: () => boolean, until: number, then: () => void): void {
	if (done() || Date.now() >= until) {
		then();
		return;
	}
	setTimeout((): void => { waitFor(done, until, then); }, 100);
}

function notifyAuthorized(): boolean {
	const auth = chromeNotifyAuth();
	if (auth >= (0 as int32)) notifyAuth = auth;
	chromeNotifyQuery();
	return notifyAuth === AUTHORIZED;
}

function act(win: Window, web: Webview, root: Ptr<void>, i: int32): void {
	if (i === 0) {
		stepName = "tray";
		installTray(TRAY);
		if (person) console.log(`ACTION click '${TRAY}' in the menu bar`);
		else chromeTrayClick(TRAY);
	} else if (i === 1) {
		stepName = "content protection off";
		console.log(`CAPTURE ${chromeWindowNumber(root)} off`);
	} else if (i === 2) {
		stepName = "content protection on";
		setWindowContentProtected(win, true);
		console.log(`CAPTURE ${chromeWindowNumber(root)} on`);
	} else if (i === 3) {
		stepName = "openExternal into the app's own scheme";
		setWindowContentProtected(win, false);
		openExternal(DEEP_LINK);
	} else if (i === 4) {
		stepName = "external link clicked in the page";
		if (link !== "") evalJs(web, `const a = document.createElement('a'); a.href = '${link}'; document.body.appendChild(a); a.click(); setTimeout(() => window.__ion__.post('page.href', location.href), 1500);`);
	} else if (i === 5) {
		stepName = "asset:// inside and outside the scope";
		if (assetRoot !== "") evalJs(web, `const post = (n, p) => p.then(r => r.text().then(t => window.__ion__.post(n, r.status + ':' + t))).catch(e => window.__ion__.post(n, 'error:' + e)); post('page.asset', fetch('asset://localhost${assetRoot}/asset.txt')); post('page.assetOutside', fetch('asset://localhost/etc/hosts'));`);
	} else if (i === 6) {
		stepName = person ? "file dialog answered by a person" : "file dialog cancelled";
		if (person) console.log("ACTION pick any file in the dialog and press Open");
		else chromeCancelModalAfter(1500 as int32);
		const t0 = Date.now();
		picked = fileOpen(win);
		pickedMs = Date.now() - t0;
	} else if (i === 7) {
		stepName = "notification permission";
		notify("Ion chrome", "first notification", "chrome-1");
		chromeNotifyQuery();
		console.log("ACTION allow notifications for IonChrome if macOS asks");
	} else if (i === 8) {
		stepName = "first notification";
		chromeNotifyQuery();
	} else if (i === 9) {
		stepName = "notification after permission";
		notify("Ion chrome", "second notification", "chrome-2");
		setTimeout((): void => {
			chromeNotifyQuery();
			console.log("CAPTURE 0 notification");
			if (person) console.log("ACTION click the 'second notification' banner");
		}, 1500);
	} else if (i === 10) {
		stepName = "global hotkey while another app is frontmost";
		hotkey = tryRegisterHotkeyKey(ModCtrl | ModAlt | ModCmd, "H", HOTKEY_ID);
		if (person) {
			chromeHideApp();
			console.log("ACTION press Ctrl+Option+Cmd+H");
		}
	}
}

function done(i: int32): boolean {
	if (i === 0) return messages.includes("tray.click=") && chromeTrayVisible(TRAY) === (1 as int32) && (!person || chromeAppActive() === (1 as int32));
	if (i === 3) return messages.includes(`deeplink=${DEEP_LINK} `);
	if (i === 4) return link === "" || messages.includes("page.href=");
	if (i === 5) return assetRoot === "" || (assetInside !== "" && assetOutside !== "");
	if (i === 6) return true;
	if (i === 7) return notifyAuthorized();
	if (i === 9) return person && messages.includes("notification.click=chrome-2 ");
	if (i === 10) return !person || messages.includes(`hotkey=${HOTKEY_ID} `);
	return false;
}

function waitMs(i: int32): number {
	if (i === 7 || i === 10 || (person && (i === 0 || i === 9))) return 60000;
	if (i === 1 || i === 2 || i === 9) return 2500;
	if (i === 8) return 1000;
	return 5000;
}

function verify(root: Ptr<void>, i: int32): void {
	if (i === 0) {
		check(`status item '${TRAY}' visible at the top of the screen`, chromeTrayVisible(TRAY) === (1 as int32));
		check("click delivered tray.click", messages.includes("tray.click="));
		if (person) check("a person's click activated the app and made the main window key", chromeAppActive() === (1 as int32) && chromeWindowIsKey(root) === (1 as int32));
		else console.log(`INFO [${stepName}] after a synthetic click: app active ${chromeAppActive()}, main window key ${chromeWindowIsKey(root)}`);
	} else if (i === 1) {
		check(`sharingType ${chromeSharingType(root)} is read-only (1)`, chromeSharingType(root) === (1 as int32));
	} else if (i === 2) {
		check(`sharingType ${chromeSharingType(root)} is none (0)`, chromeSharingType(root) === (0 as int32));
	} else if (i === 3) {
		check(`deeplink '${DEEP_LINK}' delivered`, messages.includes(`deeplink=${DEEP_LINK} `));
	} else if (i === 4) {
		if (link === "") {
			console.log(`SKIP [${stepName}] CHROME_LINK is not set`);
			return;
		}
		check("the page stayed on its own URL", messages.includes("page.href=data:"));
		console.log(`LINK ${link}`);
	} else if (i === 5) {
		if (assetRoot === "") {
			console.log(`SKIP [${stepName}] CHROME_ASSET_ROOT is not set`);
			return;
		}
		check(`a file under the scope reads 200 with its text (${assetInside})`, assetInside === "200:ion-asset-ok");
		check(`a file outside the scope is refused (${assetOutside})`, assetOutside.startsWith("403:"));
	} else if (i === 6) {
		if (person) {
			check(`fileOpen returned the picked path '${picked}'`, picked.startsWith("/"));
			return;
		}
		check(`fileOpen returned '${picked}' after ${pickedMs} ms`, picked === "" && pickedMs >= 1400 && pickedMs < 5000);
		check("the modal window was an NSOpenPanel", chromeCancelledOpenPanel() === (1 as int32));
	} else if (i === 7) {
		check(`notifications authorized (status ${notifyAuth})`, notifyAuth === AUTHORIZED);
	} else if (i === 8) {
		check("chrome-1 is in Notification Center", chromeNotifyDelivered("chrome-1") === (1 as int32));
	} else if (i === 9) {
		check("chrome-2 is in Notification Center", chromeNotifyDelivered("chrome-2") === (1 as int32));
		if (person) check("clicking it delivered notification.click with its id", messages.includes("notification.click=chrome-2 "));
	} else if (i === 10) {
		check(`registered (${hotkey})`, hotkey === HotkeyResult.Ok);
		unregisterHotkey(HOTKEY_ID);
		if (!person) {
			console.log(`SKIP [${stepName}] delivery needs a person: CHROME_PERSON=1`);
			return;
		}
		check(`hotkey ${HOTKEY_ID} delivered`, messages.includes(`hotkey=${HOTKEY_ID} `));
		check(`the app was not frontmost when it arrived (active ${activeAtHotkey})`, activeAtHotkey === (0 as int32));
	}
}

function step(win: Window, web: Webview, root: Ptr<void>, i: int32): void {
	if (i > LAST_STEP) {
		console.log(failures === 0 ? "chromeMacos: all PASS" : `chromeMacos: ${failures} FAIL`);
		closeWindow(win);
		return;
	}
	act(win, web, root, i);
	waitFor((): boolean => done(i), Date.now() + waitMs(i), (): void => {
		verify(root, i);
		step(win, web, root, (i + 1) as int32);
	});
}

function main(): int32 {
	if (assetRoot !== "") registerAssetScope([assetRoot]);
	const page = openPage("Ion chrome", 480 as int32, 300 as int32, "page", "data:text/html,<body>Ion chrome</body>");
	if (page === null) {
		console.log("chromeMacos: no window");
		return 1;
	}
	const win = page.window;
	const web = page.webview;
	listen((name: string, payload: string): void => {
		messages += `${name}=${payload} `;
		if (name === "hotkey") activeAtHotkey = chromeAppActive();
		if (name === "page.asset") assetInside = payload;
		if (name === "page.assetOutside") assetOutside = payload;
	});
	setTimeout((): void => { step(win, web, windowRoot(win), 0 as int32); }, 800);
	runLoop();
	return failures === 0 ? 0 : 1;
}

exit(main());
