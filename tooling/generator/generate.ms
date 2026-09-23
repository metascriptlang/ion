import { Project, Graph, Platform } from "./description";
import { resolve } from "./resolve";
import { xcodeProject } from "./xcode";
import { gradleProject, GeneratedFile, wrapperFiles } from "./gradle";
import { exists, isFile, mkdir, writeFile, readFile, chmod, realpath, removeAll } from "std/fs";
import { dirname, basename } from "std/fs/path";

function makeDirectories(path: string): Result<string, string> {
	let built = "";
	for (const segment of path.split("/")) {
		if (segment == "") continue;
		built += "/" + segment;
		if (exists(built)) continue;
		if (!mkdir(built).ok) return Result.err("cannot create output: " + built);
	}
	return Result.ok(path);
}

function isAndroid(graph: Graph): boolean {
	for (const target of graph.targets) {
		if (target.platform == Platform.Android) return true;
	}
	return false;
}

function render(graph: Graph, sourceRoot: string, compiler: string, tools: string): Result<Vec<GeneratedFile>, string> {
	if (!isAndroid(graph)) {
		const pbx = try xcodeProject(graph, sourceRoot, compiler);
		return Result.ok([{ path: graph.name + ".xcodeproj/project.pbxproj", content: pbx }]);
	}
	const files = try gradleProject(graph, sourceRoot, compiler);
	for (const path of wrapperFiles) {
		const vendored = readFile(tools + "/android/wrapper/" + basename(path));
		if (!vendored.ok) return Result.err("cannot read vendored Gradle wrapper file: " + path);
		files.push({ path, content: vendored.value });
	}
	return Result.ok(files);
}

function write(output: string, files: Vec<GeneratedFile>, graph: Graph): Result<void, string> {
	try makeDirectories(output);
	for (const file of files) {
		const path = output + "/" + file.path;
		try makeDirectories(dirname(path));
		if (!writeFile(path, file.content).ok) return Result.err("cannot write " + path);
		if (file.path == "gradlew" && !chmod(path, 493).ok) return Result.err("cannot make executable: " + path);
	}
	if (!writeFile(output + "/graph.json", JSON.stringify(graph)).ok) return Result.err("cannot write graph");
	return Result.ok(null);
}

export function generate(project: Project, root: string, output: string, compiler: string, tools: string): Result<string, string> {
	const resolved = project.resolve();
	if (!resolved.ok) return Result.err(resolved.error);
	const graph = resolved.value;
	const sourceRoot = realpath(root);
	if (sourceRoot == "") return Result.err("source directory does not exist: " + root);
	if (!isFile(compiler)) return Result.err("compiler does not exist: " + compiler);
	for (const target of graph.targets) {
		if (!isFile(sourceRoot + "/" + target.entry)) return Result.err("entry does not exist: " + target.entry);
	}
	const files = try render(graph, sourceRoot, compiler, tools);
	if (exists(output)) return Result.err("output already exists: " + output);
	const written = write(output, files, graph);
	if (!written.ok) {
		removeAll(output);
		return Result.err(written.error);
	}
	return Result.ok(isAndroid(graph) ? output : output + "/" + graph.name + ".xcodeproj");
}
