import { Project, Target, Platform } from "../description";
import { bundlePrefix } from "../plugins";
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
	return visualStudioProject(graph.value, "C:/source with spaces", "C:/tools/msc.exe", "C:/ion");
}

function render(targets: Vec<Target>): Result<Vec<GeneratedFile>, string> {
	return emit({ name: "Desk", targets, plugins: [bundlePrefix("dev.ion")] });
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
		"Desk/Desk.vcxproj", "Desk/Desk.rc", "Desk/Desk.manifest", "Desk/Desk.ms", "Desk/build.cmd",
		"Tool/Tool.vcxproj", "Tool/Tool.rc", "Tool/Tool.manifest", "Tool/Tool.ms", "Tool/build.cmd",
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
	check(script.includes("\"C:\\tools\\msc.exe\" build \"%~dp0Desk.ms\" %mode% \"--output=%out%Desk.exe\" || goto fail"), "msc builds the executable");
	check(script.includes("(set \"mode=--release\")"), "Release passes --release");
	check(script.includes(":fail\r\ndel /q \"%out%Desk.exe\" 2>nul\r\nexit /b 1"), "a failed step removes the executable");
	check(script.includes("copy /y \"C:\\ion\\vendor\\webview2\\runtime\\x64\\WebView2Loader.dll\" \"%out%\""), "loader beside the executable");
	check(script.includes("if exist \"%out%resources\" rmdir /s /q \"%out%resources\""), "a removed asset leaves the product");
	check(script.includes("copy /y \"C:\\source with spaces\\web\\app.js\" \"%out%resources\\web\\app.js\""), "assets keep their relative path under resources");
	check(script.includes("if not exist \"%out%resources\\web\" mkdir"), "asset directories are created");
	check(!file(files, "Tool/build.cmd").includes("resources\\"), "a target without assets copies none");

	const entry = file(files, "Desk/Desk.ms");
	check(entry == "@link(\"./obj/Desk.res\");\nimport \"C:/source with spaces/app/main\";\n", "entry links the resource as a declared input: " + entry);
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
expectError([{ ...app, assets: ["100%.html"] }], "asset cannot be used in a cmd build script: C:/source with spaces/100%.html");
const mac: Target = { ...Target.app("Mac", "main.ms"), assets: ["index.html"] };
const macAssets = resolve({ name: "Desk", targets: [mac], plugins: [bundlePrefix("dev.ion")] });
check(!macAssets.ok && macAssets.error == "assets are copied only for Windows targets; 'Mac' declares 'index.html'", "assets refused off Windows");
console.log("windows: " + passed.toString() + " assertions passed");
