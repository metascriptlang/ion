// Dispatch test — action callback fires with parsed args.

import { cli, runWith } from "../index";

let _ranName: string = "";
let _ranEntry: string = "";
let _ranStrip: boolean = false;
let _ranAssets: string[] = [];

test "action fires on subcommand match" {
	_ranName = "";
	const app = cli("test", "0.0.0");
	app.command("build <entry>", "Build")
		.option("--strip", "Strip", false)
		.action((args) => {
			_ranName = "build";
			_ranEntry = args.positional("entry");
			_ranStrip = args.flag("strip");
		});

	runWith(app, ["test", "build", "src/main.ms", "--strip"]);

	assert _ranName === "build";
	assert _ranEntry === "src/main.ms";
	assert _ranStrip === true;
}

test "string option --name=value" {
	_ranEntry = "";
	const app = cli("test", "0.0.0");
	app.command("app <bin>", "")
		.option("--icon <path>", "", false)
		.action((args) => {
			_ranEntry = args.string("icon", "");
		});

	runWith(app, ["test", "app", "out/foo", "--icon=icon.icns"]);
	assert _ranEntry === "icon.icns";
}

test "string option --name value (separate token)" {
	_ranEntry = "";
	const app = cli("test", "0.0.0");
	app.command("app <bin>", "")
		.option("--icon <path>", "", false)
		.action((args) => {
			_ranEntry = args.string("icon", "");
		});

	runWith(app, ["test", "app", "out/foo", "--icon", "icon.icns"]);
	assert _ranEntry === "icon.icns";
}

test "boolean flag default false when omitted" {
	_ranStrip = true;
	const app = cli("test", "0.0.0");
	app.command("build <entry>", "")
		.option("--strip", "", false)
		.action((args) => {
			_ranStrip = args.flag("strip");
		});

	runWith(app, ["test", "build", "x.ms"]);
	assert _ranStrip === false;
}

test "repeatable option collects to multi array" {
	_ranAssets = [];
	const app = cli("test", "0.0.0");
	app.command("app <bin>", "")
		.option("--asset <path>", "Asset", true)
		.action((args) => {
			_ranAssets = args.multi("asset");
		});

	runWith(app, ["test", "app", "out/foo", "--asset=a.png", "--asset", "b.png"]);
	assert _ranAssets.length === 2;
	assert _ranAssets[0] === "a.png";
	assert _ranAssets[1] === "b.png";
}

test "subcommand routing — only matching cmd's action fires" {
	_ranName = "";
	const app = cli("test", "0.0.0");
	app.command("foo", "").action((args) => { _ranName = "foo"; });
	app.command("bar", "").action((args) => { _ranName = "bar"; });

	runWith(app, ["test", "bar"]);
	assert _ranName === "bar";
}
