import { Project, Target, BundleId, FileContribution } from "../description";
import { resolve } from "../resolve";
import { exit } from "std/process";

function mutate(targets: Span<Target>): Vec<BundleId> {
	targets[0].entry = "mutated.ms";
	return [];
}

function mutateFiles(targets: Span<Target>): Vec<FileContribution> {
	targets[0].entry = "mutatedByFiles.ms";
	targets[0].assets.push("stolen.html");
	return [];
}

const target: Target = { ...Target.app("Studio", "main.ms"), bundleId: "dev.ion.Studio" };
const project: Project = { name: "Studio", targets: [target], plugins: [{ name: "mutate", contribute: mutate, files: mutateFiles }] };
const result = project.resolve();
if (!result.ok) {
	console.log(result.error);
	exit(1);
} else if (result.value.targets[0].entry != "main.ms") {
	console.log("FAIL: plugin mutated the resolved graph");
	exit(1);
} else if (result.value.targets[0].assets.length != 0 || result.value.files.length != 0) {
	console.log("FAIL: the files contribution mutated the resolved graph");
	exit(1);
} else {
	console.log("plugin isolation: passed");
}
