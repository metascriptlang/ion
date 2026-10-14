import { runLoop, closeWindow } from "../../src/index";
import { openPage } from "../content/page";
import { env, exit } from "std/process";

const page = "data:text/html;charset=utf-8,<html><body style='font:24px system-ui;padding:48px'><h1>Ion Generator POC</h1><p>MetaScript manifest + plugin → Raiser → Xcode → Ion window.</p></body></html>";
const opened = openPage("Ion Generator POC", 900 as int32, 560 as int32, "main", page);
if (opened === null) exit(1);
console.log("Ion Generator window created");
if (env.get("ION_GENERATOR_SMOKE") == "1") closeWindow(opened.window);
else runLoop();
