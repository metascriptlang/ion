import { open, close } from "../../src/window";
import { runLoop } from "../../src/ipc";
import { env, exit } from "std/process";

const page = "data:text/html;charset=utf-8,<html><body style='font:24px system-ui;padding:48px'><h1>Ion Generator POC</h1><p>MetaScript manifest + plugin → Raiser → Xcode → Ion window.</p></body></html>";
if (!open("Ion Generator POC", 900, 560, page)) exit(1);
console.log("Ion Generator window created");
if (env.get("ION_GENERATOR_SMOKE") == "1") close();
else runLoop();
