import {
	Project,
	Target,
	Graph,
	Plugin,
	BundleId,
	FileContribution,
	Placement,
	Artifact,
	Platform,
	Arch,
	Slot,
} from "../description";
import { bundlePrefix } from "../plugins";
import { resolve } from "../resolve";
import { xcodeProject } from "../xcode";
import { slotName } from "../description";
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
		check(true, message);
	}
}

function claim(value: string): Plugin {
	return {
		name: "claim",
		contribute: (targets: Span<Target>): Vec<BundleId> => [{ target: "Missing", value }],
		files: (targets: Span<Target>): Vec<FileContribution> => [],
	};
}

function artifact(name: string, platform: Platform, arch: Arch, file: string): Artifact {
	return { name, license: "MIT", slices: [{ platform, arch, files: [file] }] };
}

function places(artifact: Artifact, slot: Slot, directory: string): Placement {
	return { artifact, slot, directory };
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
expectError(
	resolve({ ...project, targets: [{ ...app, deploymentTarget: "15.0 -bad" }] }),
	"malformed deployment target is rejected",
);
const mobile: Target = {
	...Target.iosApp("Mobile", "main.ms"),
	deploymentTarget: "16.0",
};
const mobileGraph = resolve({ ...project, targets: [mobile] });
check(mobileGraph.ok, "iOS manifest resolves");
if (mobileGraph.ok) {
	const rendered = xcodeProject(mobileGraph.value, "/source path", "/compiler path/msc");
	check(rendered.ok, "resolved iOS graph emits an Xcode application");
	check(
		mobileGraph.value.targets[0].platform == Platform.Ios &&
			mobileGraph.value.targets[0].deploymentTarget == "16.0",
		"resolution preserves declared iOS SDK and minimum",
	);
}
const mixed = resolve({ ...project, targets: [app, mobile] });
if (mixed.ok) {
	const rendered = xcodeProject(mixed.value, "/source", "/compiler");
	check(!rendered.ok, "mixed SDK graph is rejected");
} else {
	check(false, "mixed graph resolves before emitter checks SDK compatibility");
}

const helper = artifact("helper", Platform.Macos, Arch.Arm64, "vendor/helper");
const config = artifact("config", Platform.Macos, Arch.Arm64, "vendor/config.json");
const library = artifact("lib", Platform.Macos, Arch.Arm64, "vendor/libplug.dylib");
const placed: Target = {
	...app,
	assets: ["index.html", "web/app.js"],
	files: [
		places(helper, Slot.Executables, ""),
		places(library, Slot.Libraries, "plugins"),
		places(config, Slot.Resources, "etc"),
	],
};
const placedGraph = resolve({ ...project, targets: [placed] });
check(placedGraph.ok, "macOS target with assets and one placement per slot resolves");
if (placedGraph.ok) {
	let described: Vec<string> = [];
	for (const file of placedGraph.value.files) {
		described.push(file.owner + ":" + slotName(file.slot) + ":" + file.source + ">" + file.destination);
	}
	check(described.join(" ") == [
		"manifest:Executables:vendor/helper>helper",
		"manifest:Libraries:vendor/libplug.dylib>plugins/libplug.dylib",
		"manifest:Resources:vendor/config.json>etc/config.json",
		"manifest:Resources:index.html>index.html",
		"manifest:Resources:web/app.js>web/app.js",
	].join(" "), "manifest files come first, then assets: " + described.join(" "));
	const xcode = xcodeProject(placedGraph.value, "/source", "/compiler");
	check(xcode.ok, "placements render in an Xcode project");
	if (xcode.ok) {
		const text = xcode.value;
		check(text.includes("dstPath = \"\"; dstSubfolderSpec = 6; files = (000000000000000000300000,);"), "Executables phase uses spec 6");
		check(text.includes("dstPath = \"plugins\"; dstSubfolderSpec = 10;"), "Libraries phase uses spec 10 (Frameworks)");
		check(text.includes("dstPath = \"etc\"; dstSubfolderSpec = 7;"), "Resources phase uses spec 7");
		check(text.includes("dstPath = \"web\"; dstSubfolderSpec = 7;"), "an asset directory is the phase dstPath");
		check(text.includes("path = \"/source/vendor/libplug.dylib\"; sourceTree = \"<absolute>\";"), "files are absolute references");
		check(text.includes("buildPhases = (000000000000000000000105,000000000000000000500000,"), "copy phases follow the shell phase");
		let seen: Vec<string> = [];
		for (const line of text.split("\n")) {
			if (line.length < 28 || line.slice(24, 27) != " = ") continue;
			const identifier = line.slice(0, 24);
			check(!seen.includes(identifier), "object id is unique: " + identifier);
			seen.push(identifier);
		}
		check(seen.length > 20, "object ids were scanned");
	}
}
const macAssets = resolve({ ...project, targets: [{ ...app, assets: ["index.html"] }] });
check(macAssets.ok, "assets are accepted off Windows");
expectError(
	resolve({ ...project, targets: [{ ...Target.androidApp("Mobile", "main.ms"), assets: ["index.html"], bundleId: "dev.ion.Mobile" }] }),
	"files are not placed for Android targets yet; manifest places 'index.html' into 'Mobile'",
);
expectError(
	resolve({ ...project, targets: [{ ...app, assets: ["../secret.txt"] }] }),
	"asset of 'Studio' must be a relative path inside the source directory: ../secret.txt",
);
const duplicate: Plugin = {
	name: "again",
	contribute: (targets: Span<Target>): Vec<BundleId> => [],
	files: (targets: Span<Target>): Vec<FileContribution> => [{ target: "Studio", placement: places(helper, Slot.Executables, "") }],
};
const deduped = resolve({
	...project,
	targets: [{ ...app, files: [places(helper, Slot.Executables, "")] }],
	plugins: [bundlePrefix("dev.ion"), duplicate, duplicate],
});
check(deduped.ok, "the same source at the same destination is not a conflict");
if (deduped.ok) check(deduped.value.files.length == 1, "the same placement is recorded once");
const rival = artifact("rival", Platform.Macos, Arch.Arm64, "other/helper");
const conflicting = resolve({
	...project,
	targets: [{ ...app, files: [places(helper, Slot.Executables, "")] }],
	plugins: [bundlePrefix("dev.ion"), { ...duplicate, name: "rival", files: (targets: Span<Target>): Vec<FileContribution> => [{ target: "Studio", placement: places(rival, Slot.Executables, "") }] }],
});
check(!conflicting.ok, "two sources for one destination conflict");
if (!conflicting.ok) {
	check(
		conflicting.error == "file conflict for 'Studio': manifest places 'vendor/helper' at Executables 'helper', " +
			"plugin rival places 'other/helper' at Executables 'helper'",
		conflicting.error,
	);
}
const otherSlot = resolve({
	...project,
	targets: [{ ...app, files: [places(helper, Slot.Executables, ""), places(rival, Slot.Resources, "")] }],
});
check(otherSlot.ok, "one destination name in two slots is not a conflict");
console.log("resolve: " + passed.toString() + " assertions passed");
