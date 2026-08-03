// Tauri-style command: JS calls `await window.ion.call(name, args)`, MS
// handler receives args as a raw JSON string and returns a JSON string.
// The result is sent back to JS and resolves the awaiting Promise.
//
// Example:
//
//   import { command } from "@metascript/ion";
//   import { parseJson } from "std/serialize/json/parser";
//   import { asInt32, getDynamicField } from "std/serialize/json/accessors";
//
//   command("addNumbers", (argsJson) => {
//     const args = parseJson(argsJson).value;
//     const a = asInt32(getDynamicField(args, "a"));
//     const b = asInt32(getDynamicField(args, "b"));
//     return `${a + b}`;
//   });
//
//   // JS: const sum = await window.ion.call("addNumbers", { a: 3, b: 5 });
//
// Wire protocol: JS posts envelope `{id, name, args}` on channel "__call".
// MS posts response `{id, value}` (or `{id, error}`) on channel "__response".
// JS bootstrap intercepts "__response" inside its closure and resolves the
// matching pending Promise — users can't override the response handler.

import { listen, invoke } from "./ipc";
import { ionEvalJS } from "./platform/bridge.h";
import { jsEscape } from "./internal/jsEscape";
import { parseJson } from "std/serialize/json/parser";
import { stringify } from "std/serialize/json/stringify";
import { asString, getDynamicField } from "std/serialize/json/accessors";

export type Command = (argsJson: string) => string;

const _cmdNames: string[] = [];
const _cmdFns: Command[] = [];
let _cmdDispatchInstalled = false;

export function command(name: string, fn: Command): void {
	_cmdNames.push(name);
	_cmdFns.push(fn);
	ensureCmdDispatch();
}

function ensureCmdDispatch(): void {
	if (_cmdDispatchInstalled) return;
	_cmdDispatchInstalled = true;
	listen((n, payload) => {
		if (n === "__call") dispatchCall(payload);
	});
}

// Standalone fn (not inline lambda) so `return;` is unambiguously void.
// Inline-lambda variant trips MS lambda return-type inference (Bug 5 family).
function dispatchCall(payload: string): void {
	const parsed = parseJson(payload);
	if (!parsed.ok) {
		respondError("?", `bad envelope: ${parsed.error}`);
		return;
	}
	const env = parsed.value;
	const id = asString(getDynamicField(env, "id"));
	const cmdName = asString(getDynamicField(env, "name"));
	const argsField = getDynamicField(env, "args");
	// Forward the raw JSON of `args` so handlers can decide their own parse.
	const argsJson = stringify(argsField, false);

	// Linear scan — Map<string, function> hits MS Bug 5; v0 handler counts
	// stay small enough that O(n) lookup is fine. Pull function value into
	// a local before calling — direct `_cmdFns[i](...)` indexed-call
	// codegens to non-callable msClosure (Bug 5 again).
	for (let i = 0; i < _cmdNames.length; i = i + 1) {
		if (_cmdNames[i] === cmdName) {
			const fn = _cmdFns[i];
			const result = fn(argsJson);
			respondValue(id, result);
			return;
		}
	}
	respondError(id, `no command: ${cmdName}`);
}

function respondValue(id: string, valueJson: string): void {
	// {"id":"<id>","value":<valueJson>} — value is raw JSON, not re-encoded.
	const env = `{"id":"${jsEscape(id)}","value":${valueJson}}`;
	ionEvalJS(`if(window.__ion__&&window.__ion__._dispatch)window.__ion__._dispatch("__response","${jsEscape(env)}")`);
}

function respondError(id: string, message: string): void {
	const env = `{"id":"${jsEscape(id)}","error":"${jsEscape(message)}"}`;
	ionEvalJS(`if(window.__ion__&&window.__ion__._dispatch)window.__ion__._dispatch("__response","${jsEscape(env)}")`);
}
