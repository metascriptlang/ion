import { Graph, Target, Platform, platformName } from "./description";
import { GeneratedFile } from "./gradle";

const cppProjectType = "8BC9CEB8-8B4A-11D0-8D11-00A0C91BC942";
const configurations: Vec<string> = ["Debug", "Release"];

function crlf(values: string[]): string {
	return values.join("\r\n") + "\r\n";
}

function xml(value: string): string {
	return value.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll("\"", "&quot;");
}

function rcString(value: string): string {
	return "\"" + value.replaceAll("\"", "\"\"") + "\"";
}

function windowsPath(path: string): string {
	return path.replaceAll("/", "\\");
}

function hex32(value: int64): string {
	const digits = "0123456789ABCDEF";
	let text = "";
	for (let shift: int64 = 28; shift >= 0; shift -= 4) {
		const digit = ((value >> shift) & 15) as int32;
		text += digits.slice(digit, digit + 1);
	}
	return text;
}

function fnv1a(text: string): int64 {
	let hash: int64 = 2166136261;
	for (let i = 0; i < text.byteLength; i += 1) {
		hash = ((hash ^ (text.byteAt(i) as int64)) * 16777619) & 4294967295;
	}
	return hash;
}

export function projectGuid(name: string): string {
	let digits = "";
	for (let part = 0; part < 4; part += 1) digits += hex32(fnv1a("ion.windows." + name + "#" + part.toString()));
	return digits.slice(0, 8) + "-" + digits.slice(8, 12) + "-" + digits.slice(12, 16) + "-" +
		digits.slice(16, 20) + "-" + digits.slice(20, 32);
}

function cmdSafe(label: string, path: string): Result<string, string> {
	if (path.includes("%") || path.includes("\"") || path.includes("!")) {
		return Result.err(label + " cannot be used in a cmd build script: " + path);
	}
	return Result.ok(windowsPath(path));
}

function validAsset(asset: string): boolean {
	if (asset == "" || asset.startsWith("/") || asset.startsWith("\\") || asset.includes(":")) return false;
	for (const segment of asset.replaceAll("\\", "/").split("/")) {
		if (segment == "" || segment == "." || segment == "..") return false;
	}
	return true;
}

function solution(graph: Graph): string {
	let out: string[] = [
		"Microsoft Visual Studio Solution File, Format Version 12.00",
		"# Visual Studio Version 17",
		"VisualStudioVersion = 17.0.31903.59",
		"MinimumVisualStudioVersion = 10.0.40219.1",
	];
	for (const target of graph.targets) {
		out.push("Project(\"{" + cppProjectType + "}\") = \"" + target.name + "\", \"" + target.name + "\\" + target.name +
			".vcxproj\", \"{" + projectGuid(target.name) + "}\"");
		if (target.dependencies.length > 0) {
			out.push("\tProjectSection(ProjectDependencies) = postProject");
			for (const dependency of target.dependencies) {
				const guid = projectGuid(dependency);
				out.push("\t\t{" + guid + "} = {" + guid + "}");
			}
			out.push("\tEndProjectSection");
		}
		out.push("EndProject");
	}
	out = out.concat(["Global", "\tGlobalSection(SolutionConfigurationPlatforms) = preSolution"]);
	for (const configuration of configurations) out.push("\t\t" + configuration + "|x64 = " + configuration + "|x64");
	out = out.concat(["\tEndGlobalSection", "\tGlobalSection(ProjectConfigurationPlatforms) = postSolution"]);
	for (const target of graph.targets) {
		const guid = projectGuid(target.name);
		for (const configuration of configurations) {
			out.push("\t\t{" + guid + "}." + configuration + "|x64.ActiveCfg = " + configuration + "|x64");
			out.push("\t\t{" + guid + "}." + configuration + "|x64.Build.0 = " + configuration + "|x64");
		}
	}
	out = out.concat([
		"\tEndGlobalSection",
		"\tGlobalSection(SolutionProperties) = preSolution",
		"\t\tHideSolutionNode = FALSE",
		"\tEndGlobalSection",
		"EndGlobal",
	]);
	return crlf(out);
}

function vcxproj(target: Target, root: string): string {
	let out: string[] = [
		"<?xml version=\"1.0\" encoding=\"utf-8\"?>",
		"<Project DefaultTargets=\"Build\" xmlns=\"http://schemas.microsoft.com/developer/msbuild/2003\">",
		"  <ItemGroup Label=\"ProjectConfigurations\">",
	];
	for (const configuration of configurations) {
		out = out.concat([
			"    <ProjectConfiguration Include=\"" + configuration + "|x64\">",
			"      <Configuration>" + configuration + "</Configuration>",
			"      <Platform>x64</Platform>",
			"    </ProjectConfiguration>",
		]);
	}
	const build = "call \"$(MSBuildProjectDirectory)\\build.cmd\" $(Configuration) \"$(OutDir)\" \"$(IntDir)\"";
	const clean = "if exist \"$(OutDir)\" rmdir /s /q \"$(OutDir)\" &amp; if exist \"$(IntDir)msc\" rmdir /s /q \"$(IntDir)msc\"";
	out = out.concat([
		"  </ItemGroup>",
		"  <PropertyGroup Label=\"Globals\">",
		"    <ProjectGuid>{" + projectGuid(target.name) + "}</ProjectGuid>",
		"    <ProjectName>" + target.name + "</ProjectName>",
		"    <WindowsTargetPlatformVersion>10.0</WindowsTargetPlatformVersion>",
		"  </PropertyGroup>",
		"  <Import Project=\"$(VCTargetsPath)\\Microsoft.Cpp.Default.props\" />",
		"  <PropertyGroup Label=\"Configuration\">",
		"    <ConfigurationType>Makefile</ConfigurationType>",
		"    <PlatformToolset>v143</PlatformToolset>",
		"  </PropertyGroup>",
		"  <Import Project=\"$(VCTargetsPath)\\Microsoft.Cpp.props\" />",
		"  <PropertyGroup>",
		"    <OutDir>$(MSBuildProjectDirectory)\\..\\bin\\" + target.name + "\\$(Configuration)\\</OutDir>",
		"    <IntDir>$(MSBuildProjectDirectory)\\obj\\$(Configuration)\\</IntDir>",
		"    <NMakeOutput>$(OutDir)" + target.name + ".exe</NMakeOutput>",
		"    <NMakeBuildCommandLine>" + build + "</NMakeBuildCommandLine>",
		"    <NMakeReBuildCommandLine>" + clean + " &amp; " + build + "</NMakeReBuildCommandLine>",
		"    <NMakeCleanCommandLine>" + clean + "</NMakeCleanCommandLine>",
		"    <LocalDebuggerWorkingDirectory>$(OutDir)</LocalDebuggerWorkingDirectory>",
		"  </PropertyGroup>",
		"  <ItemGroup>",
		"    <None Include=\"" + xml(windowsPath(root + "/" + target.entry)) + "\" />",
	]);
	for (const asset of target.assets) out.push("    <None Include=\"" + xml(windowsPath(root + "/" + asset)) + "\" />");
	out = out.concat([
		"    <None Include=\"" + target.name + ".ms\" />",
		"    <None Include=\"" + target.name + ".rc\" />",
		"    <None Include=\"" + target.name + ".manifest\" />",
		"    <None Include=\"build.cmd\" />",
		"  </ItemGroup>",
		"  <Import Project=\"$(VCTargetsPath)\\Microsoft.Cpp.targets\" />",
		"</Project>",
	]);
	return crlf(out);
}

function resource(target: Target): string {
	return crlf([
		"1 24 " + rcString(target.name + ".manifest"),
		"1 VERSIONINFO",
		"FILEVERSION 1,0,0,0",
		"PRODUCTVERSION 1,0,0,0",
		"FILEOS 0x40004",
		"FILETYPE 0x1",
		"BEGIN",
		"  BLOCK \"StringFileInfo\"",
		"  BEGIN",
		"    BLOCK \"040904b0\"",
		"    BEGIN",
		"      VALUE \"FileDescription\", " + rcString(target.name),
		"      VALUE \"InternalName\", " + rcString(target.bundleId),
		"      VALUE \"OriginalFilename\", " + rcString(target.name + ".exe"),
		"      VALUE \"ProductName\", " + rcString(target.name),
		"      VALUE \"FileVersion\", \"1.0.0.0\"",
		"      VALUE \"ProductVersion\", \"1.0.0.0\"",
		"    END",
		"  END",
		"  BLOCK \"VarFileInfo\"",
		"  BEGIN",
		"    VALUE \"Translation\", 0x409, 1200",
		"  END",
		"END",
	]);
}

function manifest(target: Target): string {
	return crlf([
		"<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>",
		"<assembly xmlns=\"urn:schemas-microsoft-com:asm.v1\" manifestVersion=\"1.0\">",
		"  <assemblyIdentity type=\"win32\" name=\"" + xml(target.bundleId) + "\" version=\"1.0.0.0\" processorArchitecture=\"amd64\"/>",
		"  <compatibility xmlns=\"urn:schemas-microsoft-com:compatibility.v1\">",
		"    <application>",
		"      <supportedOS Id=\"{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}\"/>",
		"    </application>",
		"  </compatibility>",
		"  <trustInfo xmlns=\"urn:schemas-microsoft-com:asm.v3\">",
		"    <security>",
		"      <requestedPrivileges>",
		"        <requestedExecutionLevel level=\"asInvoker\" uiAccess=\"false\"/>",
		"      </requestedPrivileges>",
		"    </security>",
		"  </trustInfo>",
		"</assembly>",
	]);
}

function entryModule(target: Target, root: string): string {
	const entry = (root + "/" + target.entry.slice(0, target.entry.length - 3)).replaceAll("\\", "/");
	return "@link(" + JSON.stringify("./obj/" + target.name + ".res") + ");\n" +
		"import " + JSON.stringify(entry) + ";\n";
}

function buildScript(target: Target, root: string, compiler: string, ionRoot: string): Result<string, string> {
	const msc = try cmdSafe("compiler path", compiler);
	const loader = try cmdSafe("Ion checkout", ionRoot + "/vendor/webview2/runtime/x64/WebView2Loader.dll");
	const exe = "\"%out%" + target.name + ".exe\"";
	let out: string[] = [
		"@echo off",
		"setlocal",
		"set \"config=%~1\"",
		"set \"out=%~2\"",
		"set \"work=%~3\"",
		"if /i \"%config%\"==\"Debug\" (set \"mode=\") else if /i \"%config%\"==\"Release\" (set \"mode=--release\") " +
			"else (echo error: unsupported configuration: %config% 1>&2& exit /b 1)",
		"if not exist \"%~dp0obj\" mkdir \"%~dp0obj\"",
		"if not exist \"%work%msc\" mkdir \"%work%msc\"",
		"if not exist \"%out%\" mkdir \"%out%\"",
		"rc.exe /nologo /fo \"%~dp0obj\\" + target.name + ".res\" \"%~dp0" + target.name + ".rc\" || goto fail",
		"pushd \"%work%msc\"",
		"\"" + msc + "\" build \"%~dp0" + target.name + ".ms\" %mode% \"--output=%out%" + target.name + ".exe\" || goto fail",
		"popd",
		"copy /y \"" + loader + "\" \"%out%\" >nul || goto fail",
		"if exist \"%out%resources\" rmdir /s /q \"%out%resources\"",
	];
	for (const asset of target.assets) {
		const source = try cmdSafe("asset", root + "/" + asset);
		const destination = windowsPath(asset);
		const slash = destination.lastIndexOf("\\");
		const directory = slash < 0 ? "%out%resources" : "%out%resources\\" + destination.slice(0, slash);
		out = out.concat([
			"if not exist \"" + directory + "\" mkdir \"" + directory + "\"",
			"copy /y \"" + source + "\" \"%out%resources\\" + destination + "\" >nul || goto fail",
		]);
	}
	out = out.concat(["exit /b 0", ":fail", "del /q " + exe + " 2>nul", "exit /b 1"]);
	return Result.ok(crlf(out));
}

export function visualStudioProject(graph: Graph, root: string, compiler: string, ionRoot: string): Result<Vec<GeneratedFile>, string> {
	for (const target of graph.targets) {
		if (target.platform != Platform.Windows) {
			return Result.err("Visual Studio project cannot contain the " + platformName(target.platform) + " target '" + target.name + "'");
		}
		if (target.deploymentTarget != "") {
			return Result.err("Windows target '" + target.name + "' sets deploymentTarget '" + target.deploymentTarget + "'; Windows targets have none");
		}
		if (!target.entry.endsWith(".ms")) return Result.err("Windows target '" + target.name + "' entry is not a .ms module: " + target.entry);
		for (const asset of target.assets) {
			if (!validAsset(asset)) return Result.err("asset of '" + target.name + "' must be a relative path inside the source directory: " + asset);
		}
	}
	let files: Vec<GeneratedFile> = [{ path: graph.name + ".sln", content: solution(graph) }];
	for (const target of graph.targets) {
		const directory = target.name + "/";
		files.push({ path: directory + target.name + ".vcxproj", content: vcxproj(target, root) });
		files.push({ path: directory + target.name + ".rc", content: resource(target) });
		files.push({ path: directory + target.name + ".manifest", content: manifest(target) });
		files.push({ path: directory + target.name + ".ms", content: entryModule(target, root) });
		const script = try buildScript(target, root, compiler, ionRoot);
		files.push({ path: directory + "build.cmd", content: script });
	}
	return Result.ok(files);
}
