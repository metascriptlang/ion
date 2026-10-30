import { Project, Graph, Platform, Slot } from "./description";
import { resolve } from "./resolve";
import { xcodeProject, iosEntry, iosEntryFile, infoPlists } from "./xcode";
import { gradleProject, GeneratedFile, wrapperFiles } from "./gradle";
import { visualStudioProject } from "./visualStudio";
import { exists, isFile, isDir, ensureDir, writeFile, copyFile, chmod, realpath, removeAll } from "std/fs";
import { dirname, basename, join } from "std/fs/path";

function makeDirectories(path: string): Result<void, string> {
	const created = ensureDir(path);
	if (!created.ok) return Result.err("cannot create output: " + path + ": " + created.error.message);
	return Result.ok(null);
}

function has(graph: Graph, platform: Platform): boolean {
	for (const target of graph.targets) {
		if (target.platform == platform) return true;
	}
	return false;
}

function platformGraph(graph: Graph, android: boolean): Graph {
	let result: Graph = { name: graph.name, targets: [], identities: [], files: [] };
	for (const target of graph.targets) {
		if ((target.platform == Platform.Android) == android) result.targets.push(target);
	}
	const kept = (name: string): boolean => {
		for (const target of result.targets) {
			if (target.name == name) return true;
		}
		return false;
	};
	for (const identity of graph.identities) {
		if (kept(identity.target)) result.identities.push(identity);
	}
	for (const placed of graph.files) {
		if (kept(placed.target)) result.files.push(placed);
	}
	return result;
}

export function render(graph: Graph, sourceRoot: string, compiler: string, tools: string): Result<Vec<GeneratedFile>, string> {
	if (has(graph, Platform.Windows)) return visualStudioProject(graph, sourceRoot, compiler);
	let files: Vec<GeneratedFile> = [];
	const apple = platformGraph(graph, false);
	if (apple.targets.length > 0) {
		const pbx = try xcodeProject(apple, sourceRoot, compiler);
		files.push({ path: graph.name + ".xcodeproj/project.pbxproj", content: pbx });
		if (has(apple, Platform.Ios)) files.push({ path: iosEntryFile, content: iosEntry() });
		for (const plist of try infoPlists(apple)) files.push(plist);
	}
	const android = platformGraph(graph, true);
	if (android.targets.length == 0) return Result.ok(files);
	for (const file of try gradleProject(android, sourceRoot, compiler)) files.push(file);
	return Result.ok(files);
}

function write(output: string, files: Vec<GeneratedFile>, graph: Graph, tools: string): Result<void, string> {
	try makeDirectories(output);
	for (const file of files) {
		const path = output + "/" + file.path;
		try makeDirectories(dirname(path));
		if (!writeFile(path, file.content).ok) return Result.err("cannot write " + path);
	}
	if (has(graph, Platform.Android)) {
		for (const vendored of wrapperFiles) {
			const path = output + "/" + vendored;
			try makeDirectories(dirname(path));
			if (!copyFile(tools + "/android/wrapper/" + basename(vendored), path).ok) {
				return Result.err("cannot copy vendored Gradle wrapper file: " + vendored);
			}
			if (vendored == "gradlew" && !chmod(path, 493).ok) return Result.err("cannot make executable: " + path);
		}
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
	for (const placed of graph.files) {
		const source = join(sourceRoot, placed.source);
		if (!isFile(source) && !(placed.slot == Slot.Resources && isDir(source))) {
			return Result.err("file does not exist: " + placed.source + ", placed by " + placed.owner + " into " + placed.target);
		}
	}
	const files = try render(graph, sourceRoot, compiler, tools);
	if (exists(output)) return Result.err("output already exists: " + output);
	const written = write(output, files, graph, tools);
	if (!written.ok) {
		removeAll(output);
		return Result.err(written.error);
	}
	if (has(graph, Platform.Windows)) return Result.ok(output + "/" + graph.name + ".sln");
	return Result.ok(has(graph, Platform.Android) ? output : output + "/" + graph.name + ".xcodeproj");
}
