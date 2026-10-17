import { env, execFileCapture, cwd, platform } from "std/process";
import { dirname, realpath, isFile, writeFile, remove, rmdir } from "std/fs";
import { relative, resolve } from "std/fs/path";
import { expansionFile } from "std/meta";

const generatorDirectory = @comptime { return dirname(expansionFile()); };

function existingFile(path: string, message: string): Result<string, string> {
	const resolved = realpath(path);
	if (resolved == "" || !isFile(resolved)) return Result.err(message);
	return Result.ok(resolve(resolved, cwd()));
}

function evaluatorSource(runner: string, manifest: string, generator: string, output: string, compiler: string): string {
	const manifestImport = "./" + relative(dirname(runner), manifest);
	const generatorImport = "./" + relative(dirname(runner), generator);
	return "import { project } from " + JSON.stringify(manifestImport) + ";\n"
		+ "import { generate } from " + JSON.stringify(generatorImport) + ";\n"
		+ "import { exit } from \"std/process\";\n"
		+ "const result = generate(project, " + JSON.stringify(dirname(manifest)) + ", " + JSON.stringify(output) + ", " + JSON.stringify(compiler) + ", " + JSON.stringify(dirname(generator)) + ");\n"
		+ "if (result.ok) console.log(result.value); else { console.log(result.error); exit(1); }\n";
}

function evaluate(runner: string, source: string, compiler: string): Result<string, string> {
	if (!writeFile(runner, source).ok) return Result.err("cannot write evaluator: " + runner);
	const result = execFileCapture(compiler, ["run", "--target=raiser", runner]);
	remove(runner);
	if (!result.ok) return Result.err((result.error.output + result.error.errorOutput).trim());
	return Result.ok(result.value.trim());
}

function evaluatorDirectory(): Result<string, string> {
	const temporary = platform == "windows"
		? execFileCapture("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command",
			"$ErrorActionPreference = 'Stop'; $path = Join-Path ([IO.Path]::GetTempPath()) ('ion-generator.' + [Guid]::NewGuid().ToString('N')); [IO.Directory]::CreateDirectory($path).FullName"])
		: execFileCapture("mktemp", ["-d", (env.get("TMPDIR") == "" ? "/tmp" : env.get("TMPDIR")) + "/ion-generator.XXXXXX"]);
	if (!temporary.ok) return Result.err("cannot create evaluator directory: " + temporary.error.errorOutput.trim());
	const directory = realpath(temporary.value.trim());
	if (directory == "") return Result.err("cannot resolve evaluator directory: " + temporary.value.trim());
	return Result.ok(directory);
}

export function generateFromManifest(manifestPath: string, outputPath: string, compilerPath: string): Result<string, string> {
	const named = manifestPath == "" ? "project.ms" : manifestPath;
	const manifest = try existingFile(resolve(named, cwd()), "manifest does not exist: " + named);
	const generator = try existingFile(generatorDirectory + "/generate.ms", "generator sources do not exist under " + generatorDirectory);
	const compiler = try existingFile(compilerPath, "MSC must name the compiler");
	const output = resolve(outputPath == "" ? dirname(manifest) + "/out/xcode" : outputPath, cwd());
	const directory = try evaluatorDirectory();
	const runner = directory + "/evaluate.ms";
	const evaluated = evaluate(runner, evaluatorSource(runner, manifest, generator, output, compiler), compiler);
	rmdir(directory);
	return evaluated;
}
