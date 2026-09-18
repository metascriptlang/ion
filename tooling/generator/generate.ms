import { Project } from "./description";
import { resolve } from "./resolve";
import { xcodeProject } from "./xcode";
import { exists, isFile, mkdir, writeFile, realpath } from "std/fs";

export function generate(project: Project, root: string, output: string, compiler: string): Result<string, string> {
	const resolved = project.resolve();
	if (!resolved.ok) return Result.err(resolved.error);
	const graph = resolved.value;
	const sourceRoot = realpath(root);
	if (sourceRoot == "") return Result.err("source directory does not exist: " + root);
	if (!isFile(compiler)) return Result.err("compiler does not exist: " + compiler);
	for (const target of graph.targets) {
		if (!isFile(sourceRoot + "/" + target.entry)) return Result.err("entry does not exist: " + target.entry);
	}
	const rendered = xcodeProject(graph, sourceRoot, compiler);
	if (!rendered.ok) return Result.err(rendered.error);
	if (exists(output)) return Result.err("output already exists: " + output);
	if (!mkdir(output).ok) return Result.err("cannot create output: " + output);
	const projectPath = output + "/" + graph.name + ".xcodeproj";
	if (!mkdir(projectPath).ok) return Result.err("cannot create project: " + projectPath);
	if (!writeFile(projectPath + "/project.pbxproj", rendered.value).ok) return Result.err("cannot write project");
	if (!writeFile(output + "/graph.json", JSON.stringify(graph)).ok) return Result.err("cannot write graph");
	return Result.ok(projectPath);
}
