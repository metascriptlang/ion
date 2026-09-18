// Hot-update behavior test app. Same shape as helloWebview but:
//   - registers ion://localhost/ → resourcePath() + "/web"  (subdir convention)
//   - opens window at ion://localhost/index.html
// So Contents/Resources/web/ is what hot-update's applyWebview swaps.

import { open, runLoop, listen, registerStaticProtocol, resourcePath } from "../src/index";

function main(): int32 {
	const webDir = resourcePath() + "/web";
	registerStaticProtocol("ion", webDir);
	const ok = open("Hot Update Test", 700 as int32, 500 as int32,
	                "ion://localhost/index.html");
	if (ok === 0) { console.log("open failed"); return 1 as int32; }
	listen((name: string, payload: string) => {
		console.log(`msg ${name}: ${payload}`);
	});
	runLoop();
	return 0 as int32;
}
