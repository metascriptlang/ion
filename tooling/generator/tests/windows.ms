import {
	Project,
	Slice,
	Placement,
	Target,
	Platform,
	Arch,
	Slot,
	Artifact,
	Plugin,
	Graph,
	BundleId,
	FileContribution,
} from "../description";
import { bundlePrefix, webview } from "../plugins";
import { resolve } from "../resolve";
import { GeneratedFile } from "../gradle";
import { xcodeProject } from "../xcode";
import { visualStudioProject, projectGuid } from "../visualStudio";
import { exit } from "std/process";

let passed = 0;

function check(value: boolean, name: string): void {
	if (!value) {
		console.log("FAIL: " + name);
		exit(1);
	}
	passed += 1;
}

function emit(project: Project): Result<Vec<GeneratedFile>, string> {
	const graph = resolve(project);
	if (!graph.ok) return Result.err(graph.error);
	return visualStudioProject(graph.value, "C:/source with spaces", "C:/tools/msc.exe");
}

function render(targets: Vec<Target>): Result<Vec<GeneratedFile>, string> {
	return emit({ name: "Desk", targets, plugins: [bundlePrefix("dev.ion"), webview()] });
}

function expectError(targets: Vec<Target>, message: string): void {
	const rendered = render(targets);
	if (rendered.ok) {
		check(false, "expected error: " + message);
	} else {
		check(rendered.error == message, message + " (got: " + rendered.error + ")");
	}
}

function file(files: Vec<GeneratedFile>, path: string): string {
	for (const generated of files) {
		if (generated.path == path) return generated.content;
	}
	check(false, "missing generated file " + path);
	return "";
}

function slices(name: string, extension: string): Vec<Slice> {
	return [
		{ platform: Platform.Windows, arch: Arch.X64, files: ["vendor/x64/" + name + extension] },
		{ platform: Platform.Windows, arch: Arch.Arm64, files: ["vendor/arm64/" + name + extension] },
	];
}

const conptyLibrary: Artifact = { name: "conpty", license: "MIT", slices: slices("conpty", ".dll") };
const conptyHost: Artifact = { name: "openConsole", license: "MIT", slices: slices("openConsole", ".exe") };
const placements: Vec<Placement> = [
	{ artifact: conptyLibrary, slot: Slot.Libraries, directory: "" },
	{ artifact: conptyHost, slot: Slot.Executables, directory: "host" },
];

function filesPlugin(name: string, target: string, placement: Placement): Plugin {
	return {
		name,
		contribute: (targets: Span<Target>): Vec<BundleId> => [],
		files: (targets: Span<Target>): Vec<FileContribution> => [{ target, placement }],
	};
}

function resolveError(target: Target, plugins: Vec<Plugin>, message: string): void {
	const graph: Result<Graph, string> = resolve({
		name: "Desk",
		targets: [target],
		plugins: [bundlePrefix("dev.ion"), ...plugins],
	});
	if (graph.ok) {
		check(false, "expected error: " + message);
	} else {
		check(graph.error == message, message + " (got: " + graph.error + ")");
	}
}

const app: Target = { ...Target.windowsApp("Desk", "app/main.ms"), assets: ["index.html", "web/app.js"] };
check(app.platform == Platform.Windows, "windowsApp selects Windows");
check(app.deploymentTarget == "" && app.assets.length == 2, "Windows defaults");

const guid = projectGuid("Desk");
check(guid == projectGuid("Desk") && guid != projectGuid("Tool"), "project GUID derives from the name");
check(guid.length == 36 && guid.split("-").length == 5, "project GUID has the 8-4-4-4-12 shape: " + guid);

const first = render([{ ...app, dependencies: ["Tool"] }, { ...app, name: "Tool", assets: [] }]);
const second = render([{ ...app, dependencies: ["Tool"] }, { ...app, name: "Tool", assets: [] }]);
check(first.ok, "Windows graph emits a Visual Studio solution");
if (first.ok && second.ok) {
	check(JSON.stringify(first.value) == JSON.stringify(second.value), "deterministic output");
	const files = first.value;
	let paths: Vec<string> = [];
	for (const generated of files) paths.push(generated.path);
	check(paths.join(",") == [
		"Desk.sln",
		"Desk/Desk.vcxproj", "Desk/Desk.rc", "Desk/Desk.manifest", "Desk/build.cmd",
		"Tool/Tool.vcxproj", "Tool/Tool.rc", "Tool/Tool.manifest", "Tool/build.cmd",
	].join(","), "emitted file set: " + paths.join(","));

	const sln = file(files, "Desk.sln");
	check(sln.includes("\"Desk\", \"Desk\\Desk.vcxproj\", \"{" + guid + "}\""), "solution names the project by its GUID");
	check(sln.includes("ProjectSection(ProjectDependencies) = postProject\r\n\t\t{" + projectGuid("Tool") + "}"), "dependency becomes a project dependency");
	check(sln.includes("Release|x64 = Release|x64") && !sln.includes("Win32") && !sln.includes("ARM64"), "x64 only");

	const project = file(files, "Desk/Desk.vcxproj");
	check(project.includes("<ConfigurationType>Makefile</ConfigurationType>"), "msc owns the build; the project compiles nothing");
	check(!project.includes("ClCompile") && !project.includes("ResourceCompile"), "no source inventory");
	check(project.includes("<PlatformToolset>v143</PlatformToolset>"), "toolset of Build Tools 2022");
	check(project.includes("call \"$(MSBuildProjectDirectory)\\build.cmd\" $(Configuration) \"$(OutDir)\" \"$(IntDir)\""), "build step runs build.cmd");
	check(project.includes("<OutDir>$(MSBuildProjectDirectory)\\..\\bin\\Desk\\$(Configuration)\\</OutDir>"), "products stay in the generated tree, one directory per target");
	check(project.includes("<None Include=\"C:\\source with spaces\\web\\app.js\" />"), "assets are listed for the IDE");

	const script = file(files, "Desk/build.cmd");
	check(script.includes("rc.exe /nologo /fo \"%~dp0obj\\Desk.res\" \"%~dp0Desk.rc\" || goto fail"), "resource compiled by the Windows SDK");
	check(script.includes("pushd \"%work%msc\""), "msc works in the intermediate directory, not the source tree");
	check(script.includes("\"C:\\tools\\msc.exe\" build \"C:\\source with spaces\\app\\main.ms\" --target=c %mode% \"--link=%~dp0obj\\Desk.res\" \"--output=%out%Desk.exe\" || goto fail"), "msc builds the app's own entry and links the resource as a tracked input");
	check(!script.includes("--passL") && !project.includes("Desk.ms"), "no entry wrapper");
	check(script.includes("(set \"mode=--release\")"), "Release passes --release");
	check(script.includes(":fail\r\ndel /q \"%out%Desk.exe\" 2>nul\r\nexit /b 1"), "a failed step removes the executable");
	check(
		script.includes("vendor\\webview2\\runtime\\x64\\WebView2Loader.dll\" \"%out%WebView2Loader.dll\" || goto fail"),
		"webview() places the loader beside the executable",
	);
	check(script.includes("call :place \"") && !script.includes("copy /y \"C:"), "files go through the place subroutine");
	check(!script.includes("rmdir"), "the build deletes nothing it did not write");
	check(
		script.includes("call :place \"C:\\source with spaces\\web\\app.js\" \"%out%resources\\web\\app.js\" || goto fail"),
		"assets keep their relative path under resources",
	);
	check(script.includes("\r\n:place\r\nfc /b \"%~1\" \"%~2\" >nul 2>&1 && exit /b 0\r\n"), "an identical file is skipped");
	check(script.includes("do if not exist \"%%~dpd\" mkdir \"%%~dpd\"\r\n"), "the destination directory is created");
	check(
		script.includes("copy /y \"%~1\" \"%~2.tmp\" >nul || exit /b 1\r\nmove /y \"%~2.tmp\" \"%~2\" >nul || exit /b 1\r\nexit /b 0\r\n"),
		"a changed file is copied aside, then moved into place",
	);
	check(script.indexOf("exit /b 0\r\n:fail") < script.indexOf("\r\n:place\r\n"), "the subroutine sits after the main flow");
	check(!file(files, "Tool/build.cmd").includes("resources\\"), "a target without assets places none there");

	check(script.includes("\"--link=%~dp0obj\\Desk.res\""), "--link names the compiled .res");
	check(file(files, "Desk/Desk.rc").includes("VALUE \"InternalName\", \"dev.ion.Desk\""), "version resource carries the bundle identity");
	check(file(files, "Desk/Desk.manifest").includes("name=\"dev.ion.Desk\""), "manifest identity is the bundle identity");
}

const graph = resolve({ name: "Desk", targets: [app], plugins: [bundlePrefix("dev.ion")] });
if (graph.ok) {
	const xcode = xcodeProject(graph.value, "/source", "/compiler");
	check(!xcode.ok && xcode.error == "Xcode project cannot contain the Windows target 'Desk'", "Xcode refuses Windows targets");
}
expectError([app, Target.app("Mac", "main.ms")], "Visual Studio project cannot contain the macOS target 'Mac'");
expectError([{ ...app, deploymentTarget: "10.0" }], "Windows target 'Desk' sets deploymentTarget '10.0'; Windows targets have none");
expectError([{ ...app, entry: "main.ts" }], "Windows target 'Desk' entry is not a .ms module: main.ts");
for (const asset of ["../secret.txt", "C:/abs.html", "/abs.html", "web//app.js"]) {
	expectError([{ ...app, assets: [asset] }], "asset of 'Desk' must be a relative path inside the source directory: " + asset);
}
expectError([{ ...app, assets: ["100%.html"] }], "file cannot be used in a cmd build script: C:/source with spaces/100%.html");
expectError([{ ...app, entry: "100%.ms" }], "entry cannot be used in a cmd build script: C:/source with spaces/100%.ms");
const twoSlots: Target = { ...app, assets: [], files: placements };
const placed = render([twoSlots]);
check(placed.ok, "an artifact with two slots renders");
if (placed.ok) {
	const script = file(placed.value, "Desk/build.cmd");
	check(
		script.includes("call :place \"C:\\source with spaces\\vendor\\x64\\conpty.dll\" \"%out%conpty.dll\" || goto fail"),
		"the x64 library slice sits beside the executable",
	);
	check(
		script.includes("call :place \"C:\\source with spaces\\vendor\\x64\\openConsole.exe\" \"%out%host\\openConsole.exe\" || goto fail"),
		"the x64 executable slice sits in its directory",
	);
	check(!script.includes("arm64"), "the arm64 slices are not placed");
}

const x64Only: Artifact = {
	name: "conpty",
	license: "MIT",
	slices: [{ platform: Platform.Windows, arch: Arch.X64, files: ["vendor/x64/conpty.dll"] }],
};
const x64Library: Placement = { artifact: x64Only, slot: Slot.Libraries, directory: "" };
const elsewhere: Artifact = {
	...x64Only,
	slices: [{ platform: Platform.Windows, arch: Arch.X64, files: ["other/conpty.dll"] }],
};
const manifestPlaces: Target = { ...app, assets: [], files: [x64Library] };
resolveError(
	{ ...manifestPlaces, arch: Arch.Arm64 },
	[],
	"artifact 'conpty' has no slice for Windows arm64, placed by manifest into 'Desk'",
);
resolveError(
	{ ...Target.androidApp("Desk", "main.ms"), files: [x64Library] },
	[],
	"artifact files are not placed for Android targets yet; manifest places 'conpty' into 'Desk'",
);
resolveError(
	manifestPlaces,
	[filesPlugin("x", "Desk", { artifact: elsewhere, slot: Slot.Libraries, directory: "" })],
	"file conflict for 'Desk': manifest places 'vendor/x64/conpty.dll' at Libraries 'conpty.dll', " +
		"plugin x places 'other/conpty.dll' at Libraries 'conpty.dll'",
);
resolveError(
	manifestPlaces,
	[filesPlugin("x", "Nope", x64Library)],
	"plugin x contributes to missing target 'Nope'",
);
resolveError(
	{ ...manifestPlaces, files: [{ ...x64Library, directory: "../up" }] },
	[],
	"directory '../up' of 'conpty' must be a relative path inside the slot, placed by manifest into 'Desk'",
);
const archGraph = resolve({
	name: "Desk",
	targets: [{ ...app, assets: [], arch: Arch.Arm64 }],
	plugins: [bundlePrefix("dev.ion")],
});
if (archGraph.ok) {
	const arm = visualStudioProject(archGraph.value, "C:/source", "C:/tools/msc.exe");
	check(!arm.ok && arm.error == "Windows target 'Desk' is arm64; the solution has only x64", "VS refuses arm64");
} else {
	check(false, "arm64 manifest without files resolves");
}
function artifactAt(name: string, file: string): Artifact {
	return { name, license: "MIT", slices: [{ platform: Platform.Windows, arch: Arch.X64, files: [file] }] };
}

function emitWith(target: Target, plugins: Vec<Plugin>): Result<Vec<GeneratedFile>, string> {
	return emit({ name: "Desk", targets: [target], plugins: [bundlePrefix("dev.ion"), ...plugins] });
}

function expectEmitError(target: Target, plugins: Vec<Plugin>, message: string): void {
	const rendered = emitWith(target, plugins);
	if (rendered.ok) {
		check(false, "expected error: " + message);
	} else {
		check(rendered.error == message, message + " (got: " + rendered.error + ")");
	}
}

const upperLibrary = artifactAt("upper", "other/CONPTY.DLL");
expectEmitError(
	manifestPlaces,
	[filesPlugin("x", "Desk", { artifact: upperLibrary, slot: Slot.Executables, directory: "" })],
	"file conflict for 'Desk': manifest places 'vendor/x64/conpty.dll' at '%out%conpty.dll', " +
		"plugin x places 'other/CONPTY.DLL' at '%out%CONPTY.DLL'",
);
expectEmitError(
	{ ...manifestPlaces, files: [{ artifact: artifactAt("rival", "other/DESK.EXE"), slot: Slot.Libraries, directory: "" }] },
	[],
	"file conflict for 'Desk': manifest places 'other/DESK.EXE' over the executable 'Desk.exe'",
);
expectEmitError(
	{ ...manifestPlaces, files: [{ artifact: artifactAt("rival", "other/desk.exe"), slot: Slot.Executables, directory: "" }] },
	[],
	"file conflict for 'Desk': manifest places 'other/desk.exe' over the executable 'Desk.exe'",
);
check(
	emitWith(manifestPlaces, [filesPlugin("x", "Desk", { artifact: x64Only, slot: Slot.Executables, directory: "" })]).ok,
	"the same source at the same final path is not a conflict",
);
console.log("windows: " + passed.toString() + " assertions passed");
