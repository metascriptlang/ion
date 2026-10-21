import { Graph, Target, Platform, Slot, slotName, platformName, InfoPlistKind } from "./description";
import { GeneratedFile } from "./gradle";
import { join } from "std/fs/path";

export function shellQuote(value: string): string {
	return "'" + value.replaceAll("'", "'\"'\"'") + "'";
}

function quote(value: string): string {
	return "\"" + value.replaceAll("\\", "\\\\").replaceAll("\"", "\\\"").replaceAll("\n", "\\n").replaceAll("\r", "\\r") + "\"";
}

function id(value: int32): string {
	return value.toString().padStart(24, "0");
}

function buildSettings(target: Target): string {
	const orientations = quote("UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown " +
		"UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight");
	const platform = match (target.platform) {
		Platform.Macos => "SDKROOT = macosx; SUPPORTED_PLATFORMS = macosx; " +
			"MACOSX_DEPLOYMENT_TARGET = " + quote(target.deploymentTarget) + "; ",
		Platform.Ios => "SDKROOT = iphoneos; SUPPORTED_PLATFORMS = \"iphoneos iphonesimulator\"; " +
			"IPHONEOS_DEPLOYMENT_TARGET = " + quote(target.deploymentTarget) + "; " +
			"TARGETED_DEVICE_FAMILY = \"1,2\"; " +
			"INFOPLIST_KEY_UILaunchScreen_Generation = YES; " +
			"INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES; " +
			"INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = " + orientations + "; " +
			"INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = " + orientations + "; " +
			"CURRENT_PROJECT_VERSION = 1; MARKETING_VERSION = 1.0; ",
		Platform.Android => "",
		Platform.Windows => "",
	};
	const signing = target.developmentTeam == "" ? "CODE_SIGNING_ALLOWED = NO; " :
		"CODE_SIGN_STYLE = Automatic; DEVELOPMENT_TEAM = " + quote(target.developmentTeam) + "; ";
	const infoPlist = target.infoPlist.length == 0 ? "" : "INFOPLIST_FILE = " + quote(infoPlistFile(target)) + "; ";
	return platform + signing + infoPlist + "ENABLE_USER_SCRIPT_SANDBOXING = NO; " +
		"GENERATE_INFOPLIST_FILE = YES; PRODUCT_NAME = " + quote(target.name) + "; " +
		"PRODUCT_BUNDLE_IDENTIFIER = " + quote(target.bundleId) + "; " +
		"INFOPLIST_KEY_CFBundleDisplayName = " + quote(target.name) + ";";
}

function infoPlistFile(target: Target): string {
	return target.name + "-Info.plist";
}

function xmlText(value: string): string {
	return value.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");
}

// Xcode merges INFOPLIST_FILE with the keys GENERATE_INFOPLIST_FILE writes; INFOPLIST_KEY_* covers a fixed set only.
export function infoPlists(graph: Graph): Result<Vec<GeneratedFile>, string> {
	let files: Vec<GeneratedFile> = [];
	for (const target of graph.targets) {
		if (target.infoPlist.length == 0) continue;
		let body = "";
		let keys: Vec<string> = [];
		for (const entry of target.infoPlist) {
			if (entry.key == "" || keys.includes(entry.key)) {
				return Result.err("target '" + target.name + "' sets Info.plist key '" + entry.key + "' " + (entry.key == "" ? "with no name" : "twice"));
			}
			keys.push(entry.key);
			const value = entry.kind == InfoPlistKind.Boolean ? "<" + entry.value + "/>" : "<string>" + xmlText(entry.value) + "</string>";
			body += "\t<key>" + xmlText(entry.key) + "</key>\n\t" + value + "\n";
		}
		files.push({
			path: infoPlistFile(target),
			content: "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" +
				"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n" +
				"<plist version=\"1.0\">\n<dict>\n" + body + "</dict>\n</plist>\n",
		});
	}
	return Result.ok(files);
}

export const iosEntryFile = "IonMain.m";

export function iosEntry(): string {
	return "#import <Foundation/Foundation.h>\n\n" +
		"extern void MsMain(void);\nextern int cmdCount;\nextern char **cmdLine;\nextern char **gEnv;\nextern int msProgramResult;\n\n" +
		"int main(int argc, char **argv, char **env) {\n" +
		"\tcmdCount = argc;\n\tcmdLine = argv;\n\tgEnv = env;\n" +
		"\t@autoreleasepool {\n\t\tMsMain();\n\t}\n" +
		"\treturn msProgramResult;\n}\n";
}

function iosScript(entry: string, compiler: string): string {
	return "set -eu\ncompiler=" + shellQuote(compiler) + "\nentry=" + shellQuote(entry) + "\n" +
		"output=\"$TARGET_BUILD_DIR/$EXECUTABLE_PATH\"\n" +
		"trap 'status=$?; if [ \"$status\" -ne 0 ]; then rm -f \"$output\"; fi' 0\n" +
		"case \"$PLATFORM_NAME\" in\n" +
		"  iphonesimulator) suffix=-simulator ;;\n" +
		"  iphoneos) suffix= ;;\n" +
		"  *) echo \"error: unsupported SDK platform: $PLATFORM_NAME\" >&2; exit 1 ;;\n" +
		"esac\n" +
		"case \"$PLATFORM_NAME/$ARCHS\" in\n" +
		"  iphoneos/arm64|iphonesimulator/arm64|iphonesimulator/x86_64) ;;\n" +
		"  *) echo \"error: unsupported architecture set: $ARCHS for $PLATFORM_NAME\" >&2; " +
		"exit 1 ;;\n" +
		"esac\n" +
		"case \"$CONFIGURATION\" in\n" +
		"  Debug) set -- ;;\n" +
		"  Release) set -- --release ;;\n" +
		"  *) echo \"error: unsupported configuration: $CONFIGURATION\" >&2; exit 1 ;;\n" +
		"esac\n" +
		"build=\"$TARGET_TEMP_DIR/msc/$CONFIGURATION/$PLATFORM_NAME/$ARCHS\"\n" +
		"mkdir -p \"$build\" \"$(dirname \"$output\")\"\ncd \"$build\"\n" +
		"\"$(xcrun --find clang)\" -c -fobjc-arc -target $ARCHS-apple-ios$IPHONEOS_DEPLOYMENT_TARGET$suffix " +
		"-isysroot \"$SDKROOT\" \"$PROJECT_DIR/" + iosEntryFile + "\" -o \"$build/IonMain.o\"\n" +
		"\"$compiler\" build \"$entry\" --os=ios --cpu=\"$ARCHS\" \"--link=$build/IonMain.o\" " +
		"--cc=\"$(xcrun --find clang)\" " +
		"\"--passC=-target $ARCHS-apple-ios$IPHONEOS_DEPLOYMENT_TARGET$suffix " +
		"-isysroot \\\"$SDKROOT\\\"\" \"--output=$output\" \"$@\"\n";
}

function copySubfolder(slot: Slot): int32 {
	return match (slot) {
		Slot.Executables => 6,
		Slot.Libraries => 10,
		Slot.Resources => 7,
	};
}

function destinationDirectory(destination: string): string {
	const slash = destination.lastIndexOf("/");
	return slash < 0 ? "" : destination.slice(0, slash);
}

struct CopyPhases {
	objects: string;
	phases: string;
	references: string;
}

function copyPhases(graph: Graph, target: Target, root: string, index: int32): CopyPhases {
	let result: CopyPhases = { objects: "", phases: "", references: "" };
	let groups: Vec<string> = [];
	let ordinal: int32 = 0;
	for (const placed of graph.files) {
		if (placed.target != target.name) continue;
		const key = slotName(placed.slot) + "|" + destinationDirectory(placed.destination);
		if (groups.includes(key)) continue;
		let members = "";
		for (const member of graph.files) {
			if (member.target != target.name) continue;
			if (slotName(member.slot) + "|" + destinationDirectory(member.destination) != key) continue;
			const buildFileId = id(300000 + index * 1000 + ordinal);
			const referenceId = id(400000 + index * 1000 + ordinal);
			members += buildFileId + ",";
			result.references += referenceId + ",";
			result.objects += `${buildFileId} = { isa = PBXBuildFile; fileRef = ${referenceId}; };\n`;
			result.objects += `${referenceId} = { isa = PBXFileReference; lastKnownFileType = file; path = ${quote(join(root, member.source))}; sourceTree = "<absolute>"; };\n`;
			ordinal += 1;
		}
		const phaseId = id(500000 + index * 1000 + groups.length);
		result.phases += phaseId + ",";
		result.objects += `${phaseId} = { isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = ${quote(destinationDirectory(placed.destination))}; dstSubfolderSpec = ${copySubfolder(placed.slot)}; files = (${members}); runOnlyForDeploymentPostprocessing = 0; };\n`;
		groups.push(key);
	}
	return result;
}

export function xcodeProject(graph: Graph, root: string, compiler: string): Result<string, string> {
	for (const target of graph.targets) {
		if (target.platform == Platform.Android || target.platform == Platform.Windows) {
			return Result.err("Xcode project cannot contain the " + platformName(target.platform) + " target '" + target.name + "'");
		}
		if (target.platform != graph.targets[0].platform) {
			return Result.err(
				"Xcode project cannot mix macOS and iOS targets: " +
				graph.targets[0].name + " and " + target.name,
			);
		}
	}
	let objects = "";
	let targets = "";
	let products = "";
	let sources = "";
	for (let i: int32 = 0; i < graph.targets.length; i += 1) {
		const target = graph.targets[i];
		const base: int32 = 100 + i * 100;
		const targetId = id(base);
		targets += targetId + ",";
		products += id(base + 1) + ",";
		sources += id(base + 6) + ",";
		let dependencies = "";
		for (let di: int32 = 0; di < target.dependencies.length; di += 1) {
			for (let ti: int32 = 0; ti < graph.targets.length; ti += 1) {
				if (graph.targets[ti].name != target.dependencies[di]) continue;
				const dependencyId = id(100000 + i * 1000 + di);
				const proxyId = id(200000 + i * 1000 + di);
				dependencies += dependencyId + ",";
				objects += `${proxyId} = { isa = PBXContainerItemProxy; containerPortal = ${id(1)}; proxyType = 1; remoteGlobalIDString = ${id(100 + ti * 100)}; remoteInfo = ${quote(graph.targets[ti].name)}; };\n`;
				objects += `${dependencyId} = { isa = PBXTargetDependency; target = ${id(100 + ti * 100)}; targetProxy = ${proxyId}; };\n`;
			}
		}
		const copies = copyPhases(graph, target, root, i);
		objects += copies.objects;
		sources += copies.references;
		const entry = root + "/" + target.entry;
		const script = target.platform == Platform.Ios ? iosScript(entry, compiler) :
			"set -eu\ncd " + shellQuote(root) +
			"\nmkdir -p \"$TARGET_BUILD_DIR/" + target.name + ".app/Contents/MacOS\"\n" +
			shellQuote(compiler) + " build " + shellQuote(target.entry) +
			" --cc=clang --output=\"$TARGET_BUILD_DIR/$EXECUTABLE_PATH\"\n";
		objects += `${targetId} = { isa = PBXNativeTarget; name = ${quote(target.name)}; productName = ${quote(target.name)}; productType = "com.apple.product-type.application"; productReference = ${id(base + 1)}; buildConfigurationList = ${id(base + 2)}; buildPhases = (${id(base + 5)},${copies.phases}); buildRules = (); dependencies = (${dependencies}); };\n`;
		objects += `${id(base + 1)} = { isa = PBXFileReference; explicitFileType = wrapper.application; path = ${quote(target.name + ".app")}; sourceTree = BUILT_PRODUCTS_DIR; };\n`;
		objects += `${id(base + 2)} = { isa = XCConfigurationList; buildConfigurations = (${id(base + 3)},${id(base + 4)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug; };\n`;
		objects += `${id(base + 3)} = { isa = XCBuildConfiguration; name = Debug; buildSettings = { ${buildSettings(target)} }; };\n`;
		objects += `${id(base + 4)} = { isa = XCBuildConfiguration; name = Release; buildSettings = { ${buildSettings(target)} }; };\n`;
		objects += `${id(base + 5)} = { isa = PBXShellScriptBuildPhase; buildActionMask = 2147483647; files = (); inputPaths = (); outputPaths = ("$(TARGET_BUILD_DIR)/$(EXECUTABLE_PATH)",); alwaysOutOfDate = 1; name = "Compile MetaScript"; runOnlyForDeploymentPostprocessing = 0; shellPath = /bin/sh; shellScript = ${quote(script)}; };\n`;
		objects += `${id(base + 6)} = { isa = PBXFileReference; lastKnownFileType = text; path = ${quote(root + "/" + target.entry)}; sourceTree = "<absolute>"; };\n`;
	}
	objects += `${id(1)} = { isa = PBXProject; attributes = { LastUpgradeCheck = 1600; }; buildConfigurationList = ${id(4)}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en,Base,); mainGroup = ${id(2)}; productRefGroup = ${id(3)}; projectDirPath = ""; projectRoot = ""; targets = (${targets}); };\n`;
	objects += `${id(2)} = { isa = PBXGroup; children = (${sources}${id(3)},); sourceTree = "<group>"; };\n`;
	objects += `${id(3)} = { isa = PBXGroup; children = (${products}); name = Products; sourceTree = "<group>"; };\n`;
	objects += `${id(4)} = { isa = XCConfigurationList; buildConfigurations = (${id(5)},${id(6)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug; };\n`;
	objects += `${id(5)} = { isa = XCBuildConfiguration; name = Debug; buildSettings = { ALWAYS_SEARCH_USER_PATHS = NO; }; };\n`;
	objects += `${id(6)} = { isa = XCBuildConfiguration; name = Release; buildSettings = { ALWAYS_SEARCH_USER_PATHS = NO; }; };\n`;
	return Result.ok(`{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n${objects}}; rootObject = ${id(1)}; }\n`);
}
