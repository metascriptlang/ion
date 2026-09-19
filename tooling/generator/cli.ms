import { env, exit, execFileCapture, cwd } from "std/process";
import { dirname, realpath, isFile, writeFile, remove, rmdir } from "std/fs";
import { relative } from "std/fs/path";
import { writeStderr } from "std/io";

function existingFile(path: string, message: string): Result<string, string> {
	const resolved = realpath(path);
	if (resolved == "" || !isFile(resolved)) return Result.err(message);
	return Result.ok(resolved);
}

function evaluatorSource(runner: string, manifest: string, generator: string, output: string, compiler: string): string {
	const manifestImport = "./" + relative(dirname(runner), manifest);
	const generatorImport = "./" + relative(dirname(runner), generator);
	return "import { project } from " + JSON.stringify(manifestImport) + ";\n"
		+ "import { generate } from " + JSON.stringify(generatorImport) + ";\n"
		+ "import { exit } from \"std/process\";\n"
		+ "const result = generate(project, " + JSON.stringify(dirname(manifest)) + ", " + JSON.stringify(output) + ", " + JSON.stringify(compiler) + ");\n"
		+ "if (result.ok) console.log(result.value); else { console.log(result.error); exit(1); }\n";
}

function evaluate(runner: string, source: string, compiler: string): Result<string, string> {
	if (!writeFile(runner, source).ok) return Result.err("cannot write evaluator: " + runner);
	const result = execFileCapture(compiler, ["run", runner, "--target=raiser"]);
	remove(runner);
	if (!result.ok) return Result.err((result.error.output + result.error.errorOutput).trim());
	return Result.ok(result.value.trim());
}

function absolute(path: string): string {
	return path.startsWith("/") ? path : cwd() + "/" + path;
}

function setting(name: string, fallback: string): string {
	const value = env.get(name);
	return value == "" ? fallback : value;
}

function run(): Result<string, string> {
	const manifestPath = setting("ION_GENERATE_MANIFEST", "project.ms");
	const manifest = try existingFile(absolute(manifestPath), "manifest does not exist: " + manifestPath);
	const root = env.get("ION_GENERATE_ROOT");
	const generator = try existingFile(root + "/tooling/generator/generate.ms", "generator sources do not exist under " + root);
	const compiler = try existingFile(env.get("MSC"), "MSC must name the compiler");
	const output = absolute(setting("ION_GENERATE_OUTPUT", dirname(manifest) + "/out/xcode"));
	const temporary = execFileCapture("/usr/bin/mktemp", ["-d", "/private/tmp/ion-generator.XXXXXX"]);
	if (!temporary.ok) return Result.err("cannot create evaluator directory");
	const directory = temporary.value.trim();
	const runner = directory + "/evaluate.ms";
	const evaluated = evaluate(runner, evaluatorSource(runner, manifest, generator, output, compiler), compiler);
	rmdir(directory);
	return evaluated;
}

const result = run();
if (result.ok) {
	console.log(result.value);
} else {
	writeStderr("ion generate: " + result.error + "\n");
	exit(1);
}
