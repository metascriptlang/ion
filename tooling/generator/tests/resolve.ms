import { Project, Target, Graph, Plugin, BundleId } from "../description";
import { bundlePrefix } from "../plugins";
import { resolve } from "../resolve";
import { exit } from "std/process";

let passed = 0;

function check(value: boolean, name: string): void {
	if (!value) {
		console.log("FAIL: " + name);
		exit(1);
	}
	passed += 1;
}

function expectError(result: Result<Graph, string>, message: string): void {
	if (result.ok) {
		check(false, "expected error: " + message);
	} else {
		check(result.error == message, message + " (got: " + result.error + ")");
	}
}

function claim(value: string): Plugin {
	return {
		name: "claim",
		contribute: (targets: Span<Target>): Vec<BundleId> => [{ target: "Missing", value }],
	};
}

const app = Target.app("Studio", "main.ms");
const tool = Target.app("Tool", "tool.ms");
const project: Project = { name: "Studio", targets: [app], plugins: [bundlePrefix("dev.ion")] };
const first = project.resolve();
check(first.ok, "resolve succeeds");
if (first.ok) {
	check(first.value.targets[0].bundleId == "dev.ion.Studio", "plugin identity");
	check(first.value.identities.length == 1, "one identity recorded");
	check(first.value.identities[0].owner == "plugin bundlePrefix(dev.ion)", "resolver stamps plugin provenance");
}
check(project.targets[0].bundleId == "", "manifest unchanged");
const second = project.resolve();
check(second.ok, "resolve twice succeeds");
if (first.ok && second.ok) check(JSON.stringify(first.value) == JSON.stringify(second.value), "deterministic graph");

const declared = resolve({ ...project, targets: [{ ...app, bundleId: "dev.ion.Studio" }] });
check(declared.ok, "matching manifest and plugin identity accepted");
if (declared.ok) check(declared.value.identities[0].owner == "manifest", "manifest provenance first");

expectError(resolve({ ...project, name: "Bad Name" }), "invalid project name: 'Bad Name'");
expectError(resolve({ ...project, targets: [] }), "project 'Studio' has no targets");
expectError(resolve({ ...project, targets: [app, app] }), "the target 'Studio' is declared multiple times");
expectError(resolve({ ...project, targets: [{ ...app, dependencies: ["Missing"] }] }), "couldn't find target 'Missing' required by 'Studio'");
expectError(resolve({ ...project, targets: [{ ...app, dependencies: ["Studio"] }] }), "circular dependency between targets: Studio -> Studio");
expectError(
	resolve({ ...project, targets: [{ ...app, dependencies: ["Tool"] }, { ...tool, dependencies: ["Studio"] }] }),
	"circular dependency between targets: Studio -> Tool -> Studio",
);
expectError(
	resolve({ ...project, plugins: [bundlePrefix("dev.one"), bundlePrefix("dev.two")] }),
	"bundle identity conflict for 'Studio': plugin bundlePrefix(dev.one) sets 'dev.one.Studio', plugin bundlePrefix(dev.two) sets 'dev.two.Studio'",
);
expectError(
	resolve({ ...project, targets: [{ ...app, bundleId: "dev.app.Studio" }] }),
	"bundle identity conflict for 'Studio': manifest sets 'dev.app.Studio', plugin bundlePrefix(dev.ion) sets 'dev.ion.Studio'",
);
expectError(resolve({ ...project, plugins: [claim("dev.x")] }), "plugin claim contributes to missing target 'Missing'");
expectError(resolve({ ...project, plugins: [] }), "missing bundle identity for 'Studio'");
console.log("resolve: " + passed.toString() + " assertions passed");
