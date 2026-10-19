// asset:// check on any platform: a page served from ion:// fetches a file under the registered scope and one outside
// it, and the program prints what each returned. ASSET_ROOT names a directory holding `asset.txt`
// with the text `ion-asset-ok`; ASSET_OUTSIDE names a readable file outside it.
//   msc build examples/assetScope.ms

import { registerAssetScope, registerStaticProtocol, closeWindow, evalJs, listen, runLoop, Webview } from "../src/index";
import { openPage } from "./content/page";
import { env, exit } from "std/process";

const root = env.get("ASSET_ROOT");
const outside = env.get("ASSET_OUTSIDE");
let inside = "";
let refused = "";
let failures = 0;
let reported = false;

function check(what: string, ok: boolean): void {
	if (!ok) failures += 1;
	console.log(`${ok ? "PASS" : "FAIL"} ${what}`);
}

function url(path: string): string {
	const slashed = path.split("\\").join("/");
	return slashed.startsWith("/") ? `asset://localhost${slashed}` : `asset://localhost/${slashed}`;
}

function ask(web: Webview): void {
	if (inside !== "" && refused !== "") return;
	evalJs(web, `const post = (n, p) => p.then(r => r.text().then(t => window.__ion__.post(n, r.status + ':' + t))).catch(e => window.__ion__.post(n, 'error:' + e)); post('asset.inside', fetch('${url(`${root}/asset.txt`)}')); post('asset.outside', fetch('${url(outside)}'));`);
	setTimeout((): void => { ask(web); }, 500);
}

function main(): int32 {
	if (root === "" || outside === "") {
		console.log("assetScope: set ASSET_ROOT and ASSET_OUTSIDE");
		return 2;
	}
	console.log(`assetScope: scope registered ${registerAssetScope([root])}, ion:// page ${registerStaticProtocol("ion", root)}`);
	const page = openPage("Ion asset", 320 as int32, 200 as int32, "page", "ion://localhost/asset.txt");
	if (page === null) {
		console.log("assetScope: no window");
		return 1;
	}
	const win = page.window;
	const web = page.webview;
	listen((name: string, payload: string): void => {
		if (name === "asset.inside") inside = payload;
		if (name === "asset.outside") refused = payload;
		if (inside === "" || refused === "" || reported) return;
		reported = true;
		check(`${url(`${root}/asset.txt`)} reads 200 with its text (${inside})`, inside === "200:ion-asset-ok");
		check(`${url(outside)} is refused (${refused})`, refused.startsWith("403:"));
		console.log(failures === 0 ? "assetScope: all PASS" : `assetScope: ${failures} FAIL`);
		closeWindow(win);
	});
	ask(web);
	runLoop();
	return failures === 0 ? 0 : 1;
}

exit(main());
