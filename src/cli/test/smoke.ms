// Minimal smoke test — focuses on data-only assertions to isolate from the
// MS class-method codegen quirks around action callbacks + array passing.

import { cli } from "../index";

test "cli() creates instance" {
	const app = cli("test", "0.0.1");
	assert app.name === "test";
	assert app.version === "0.0.1";
	assert app.commands.length === 0;
}

test "command() registers a command" {
	const app = cli("test", "0.0.0");
	app.command("build <entry>", "Build the project");
	assert app.commands.length === 1;
	assert app.commands[0].name === "build";
	assert app.commands[0].description === "Build the project";
}

test "command spec parses positional args" {
	const app = cli("test", "0.0.0");
	const c = app.command("app <bin> <name> [extra]", "");
	assert c.positionalNames.length === 3;
	assert c.positionalNames[0] === "bin";
	assert c.positionalNames[1] === "name";
	assert c.positionalNames[2] === "extra";
	assert c.positionalRequired[0] === true;
	assert c.positionalRequired[1] === true;
	assert c.positionalRequired[2] === false;
}

test "option() registers a boolean flag" {
	const app = cli("test", "0.0.0");
	const c = app.command("build <entry>", "");
	c.option("--strip", "Strip debug symbols", false);
	assert c.optNames.length === 1;
	assert c.optNames[0] === "strip";
	assert c.optHasValue[0] === false;
	assert c.optMulti[0] === false;
}

test "option() registers a string option" {
	const app = cli("test", "0.0.0");
	const c = app.command("app <bin>", "");
	c.option("--icon <path>", "Icon file", false);
	assert c.optHasValue[0] === true;
	assert c.optMulti[0] === false;
}

test "option() registers a repeatable option" {
	const app = cli("test", "0.0.0");
	const c = app.command("app <bin>", "");
	c.option("--asset <path>", "Asset", true);
	assert c.optHasValue[0] === true;
	assert c.optMulti[0] === true;
}

test "findCmd locates by name" {
	const app = cli("test", "0.0.0");
	app.command("build <entry>", "");
	app.command("app <bin>", "");
	assert app.findCmd("build") === 0;
	assert app.findCmd("app") === 1;
	assert app.findCmd("nope") === -1;
}

test "Command.findOpt locates by name" {
	const app = cli("test", "0.0.0");
	const c = app.command("build", "");
	c.option("--strip", "", false);
	c.option("--target <t>", "", false);
	assert c.findOpt("strip") === 0;
	assert c.findOpt("target") === 1;
	assert c.findOpt("nope") === -1;
}

