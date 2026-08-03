// command-builder — a tiny cac-inspired CLI library for MetaScript.
//
// Usage:
//
//   import { cli } from "../command-builder";
//
//   const app = cli("myapp", "0.1.0");
//
//   app.command("build <entry>", "Build a release binary")
//      .option("--strip", "Strip debug symbols")
//      .action((args) => {
//        const entry = args.positional("entry");
//        if (args.flag("strip")) console.log("stripping");
//      });
//
//   app.command("bundle <bin> <name>", "Wrap as .app")
//      .option("--icon <path>", "Icon file")
//      .option("--asset <path>", "Repeatable", true)
//      .action((args) => {
//        const bin = args.positional("bin");
//        const assets = args.multi("asset");
//      });
//
//   app.parse();
//
// Spec syntax (cac-style):
//   "name <required> [optional]"   — positional args
//   "--flag"                        — boolean
//   "--name <value>"                — string option
//   option(spec, desc, true)        — repeatable (returns string[])

import { argv, exit } from "std/process";

// ---- ParsedArgs ------------------------------------------------------------

export class ParsedArgs {
	_positional: Map<string, string>;
	_flags: Set<string>;
	_strings: Map<string, string>;
	_multi: Map<string, string[]>;

	constructor() {
		this._positional = new Map<string, string>();
		this._flags = new Set<string>();
		this._strings = new Map<string, string>();
		this._multi = new Map<string, string[]>();
	}

	positional(name: string): string {
		if (this._positional.has(name)) return this._positional.get(name);
		return "";
	}

	flag(name: string): boolean {
		return this._flags.has(name);
	}

	string(name: string, def: string = ""): string {
		if (this._strings.has(name)) return this._strings.get(name);
		return def;
	}

	multi(name: string): string[] {
		if (this._multi.has(name)) return this._multi.get(name);
		return [] as string[];
	}
}

// ---- Command ---------------------------------------------------------------

type ActionFn = (args: ParsedArgs) => void;

export class Command {
	name: string;
	description: string;
	positionalNames: string[];     // ["entry", "name"]
	positionalRequired: boolean[]; // true for <name>, false for [name]

	// Parallel arrays for options (Map<string, fn> hits MS Bug 5; we don't need
	// fn values per-option but keep parallel arrays for symmetry with Command.)
	optNames: string[];        // ["strip", "icon", "asset"]
	optDescs: string[];
	optHasValue: boolean[];    // true for `--name <value>`, false for boolean
	optMulti: boolean[];       // true if repeatable (collects into multi map)

	actionFn: ActionFn;
	hasAction: boolean;

	constructor(spec: string, description: string) {
		this.description = description;
		this.positionalNames = [];
		this.positionalRequired = [];
		this.optNames = [];
		this.optDescs = [];
		this.optHasValue = [];
		this.optMulti = [];
		this.hasAction = false;
		this.actionFn = (a: ParsedArgs) => {};

		// Parse spec like "build <entry> [extra]"
		const parts = spec.split(" ");
		this.name = parts[0];
		for (let i = 1; i < parts.length; i = i + 1) {
			const p = parts[i];
			if (p.length === 0) continue;
			if (p.startsWith("<") && p.endsWith(">")) {
				this.positionalNames.push(p.slice(1, p.length - 1));
				this.positionalRequired.push(true);
			} else if (p.startsWith("[") && p.endsWith("]")) {
				this.positionalNames.push(p.slice(1, p.length - 1));
				this.positionalRequired.push(false);
			}
		}
	}

	option(spec: string, desc: string = "", multi: boolean = false): Command {
		// "--strip" → boolean   "--icon <path>" → string with value
		const parts = spec.split(" ");
		const flag = parts[0]; // "--strip"
		const name = flag.startsWith("--") ? flag.slice(2 as int64, flag.length as int64) : flag;
		const hasVal = parts.length > 1;
		this.optNames.push(name);
		this.optDescs.push(desc);
		this.optHasValue.push(hasVal);
		this.optMulti.push(multi);
		return this;
	}

	action(fn: ActionFn): Command {
		this.actionFn = fn;
		this.hasAction = true;
		return this;
	}

	// Look up an option by name. Returns -1 if unknown.
	findOpt(name: string): int32 {
		for (let i = 0; i < this.optNames.length; i = i + 1) {
			if (this.optNames[i] === name) return i as int32;
		}
		return -1 as int32;
	}
}

// ---- CLI -------------------------------------------------------------------

export class CLI {
	name: string;
	version: string;
	commands: Command[];

	constructor(name: string, version: string) {
		this.name = name;
		this.version = version;
		this.commands = [];
	}

	command(spec: string, description: string = ""): Command {
		const c = new Command(spec, description);
		this.commands.push(c);
		return c;
	}

	// Find a command by name. Returns -1 if unknown.
	findCmd(name: string): int32 {
		for (let i = 0; i < this.commands.length; i = i + 1) {
			if (this.commands[i].name === name) return i as int32;
		}
		return -1 as int32;
	}

}

// Run a CLI against std/process argv. Use this in main().
export function run(app: CLI): void {
	parseAndDispatch(app, argv);
}

// Run a CLI against a custom argv. Use this from tests.
// (Top-level function, not a class method, because MS class methods that
// take `string[]` args get a stray address-of in the C codegen.)
export function runWith(app: CLI, args: string[]): void {
	parseAndDispatch(app, args);
}

// Standalone helper. Class methods that take `string[]` get a stray address-of
// in the C codegen — passing as a regular function arg works correctly.
function parseAndDispatch(self: CLI, args: string[]): void {
	// args[0] = program path; args[1] = subcommand or --help/--version
	if (args.length < 2 || args[1] === "--help" || args[1] === "-h" || args[1] === "help") {
		printHelp(self);
		return;
	}
	if (args[1] === "--version" || args[1] === "-v") {
		console.log(`${self.name} ${self.version}`);
		return;
	}

	const subName = args[1];
	const cmdIdx = self.findCmd(subName);
	if (cmdIdx < 0) {
		console.log(`error: unknown command: ${subName}`);
		console.log("");
		printHelp(self);
		exit(1);
		return;
	}
	const cmd = self.commands[cmdIdx];

	// Per-command --help
	for (let i = 2; i < args.length; i = i + 1) {
		if (args[i] === "--help" || args[i] === "-h") {
			printCommandHelp(self, cmd);
			return;
		}
	}

	// Walk remaining args, filling ParsedArgs.
	const parsed = parseCommand(cmd, args);
	if (!cmd.hasAction) {
		console.log(`error: command "${subName}" has no action`);
		exit(1);
		return;
	}
	const fn = cmd.actionFn; // extract to local before calling (MS Bug 5)
	fn(parsed);
}

function printHelp(self: CLI): void {
	console.log(`${self.name} ${self.version}`);
	console.log("");
	console.log("Commands:");
	for (let i = 0; i < self.commands.length; i = i + 1) {
		const c = self.commands[i];
		console.log(`  ${pad(c.name, 16 as int32)} ${c.description}`);
	}
	console.log("");
	console.log(`Run \`${self.name} <command> --help\` for command-specific options.`);
}

function printCommandHelp(self: CLI, cmd: Command): void {
	let usage = `${self.name} ${cmd.name}`;
	for (let i = 0; i < cmd.positionalNames.length; i = i + 1) {
		const n = cmd.positionalNames[i];
		usage = cmd.positionalRequired[i] ? `${usage} <${n}>` : `${usage} [${n}]`;
	}
	console.log(`Usage: ${usage}`);
	console.log("");
	if (cmd.description.length > 0) {
		console.log(cmd.description);
		console.log("");
	}
	if (cmd.optNames.length > 0) {
		console.log("Options:");
		for (let i = 0; i < cmd.optNames.length; i = i + 1) {
			// Probe: avoid the conditional ternary inside template literal —
			// build the line as plain string concat to test SIGTRAP hypothesis.
			let line = "  --";
			line = line + cmd.optNames[i];
			if (cmd.optHasValue[i]) line = line + " <value>";
			// pad with spaces
			while (line.length < 26) line = line + " ";
			line = line + cmd.optDescs[i];
			if (cmd.optMulti[i]) line = line + " (repeatable)";
			console.log(line);
		}
	}
}

// ---- Top-level helper ------------------------------------------------------

export function cli(name: string, version: string = "0.0.0"): CLI {
	return new CLI(name, version);
}

// ---- Internals -------------------------------------------------------------

function parseCommand(cmd: Command, args: string[]): ParsedArgs {
	const parsed = new ParsedArgs();
	let posIdx = 0;
	let i = 2; // skip prog + subcommand
	while (i < args.length) {
		const tok = args[i];
		if (tok.startsWith("--")) {
			// --name=value or --name value or --name (boolean)
			const eq = tok.indexOf("=");
			let name = "";
			let value = "";
			let hasInlineValue = false;
			if (eq >= 0) {
				name = tok.slice(2, eq);
				value = tok.slice(eq + 1, tok.length);
				hasInlineValue = true;
			} else {
				name = tok.slice(2, tok.length);
			}
			const optIdx = cmd.findOpt(name);
			if (optIdx < 0) {
				console.log(`warn: unknown option: --${name}`);
				i = i + 1;
				continue;
			}
			if (cmd.optHasValue[optIdx]) {
				if (!hasInlineValue) {
					if (i + 1 >= args.length) {
						console.log(`error: --${name} requires a value`);
						exit(1);
						return parsed;
					}
					value = args[i + 1];
					i = i + 1;
				}
				if (cmd.optMulti[optIdx]) {
					let arr: string[] = [];
					if (parsed._multi.has(name)) arr = parsed._multi.get(name);
					arr.push(value);
					parsed._multi.set(name, arr);
				} else {
					parsed._strings.set(name, value);
				}
			} else {
				parsed._flags.add(name);
			}
		} else {
			// positional
			if (posIdx < cmd.positionalNames.length) {
				parsed._positional.set(cmd.positionalNames[posIdx], tok);
				posIdx = posIdx + 1;
			}
		}
		i = i + 1;
	}
	// Validate required positionals
	for (let p = 0; p < cmd.positionalNames.length; p = p + 1) {
		if (cmd.positionalRequired[p] && !parsed._positional.has(cmd.positionalNames[p])) {
			console.log(`error: missing required argument: <${cmd.positionalNames[p]}>`);
			exit(1);
			return parsed;
		}
	}
	return parsed;
}

function pad(s: string, width: int32): string {
	let result = s;
	while (result.length < width) result = `${result} `;
	return result;
}
