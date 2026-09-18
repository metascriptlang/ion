import { Graph, Target, Platform } from "./description";

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
	return `SDKROOT = macosx; SUPPORTED_PLATFORMS = macosx; MACOSX_DEPLOYMENT_TARGET = 13.0; CODE_SIGNING_ALLOWED = NO; ENABLE_USER_SCRIPT_SANDBOXING = NO; GENERATE_INFOPLIST_FILE = YES; PRODUCT_NAME = ${quote(target.name)}; PRODUCT_BUNDLE_IDENTIFIER = ${quote(target.bundleId)}; INFOPLIST_KEY_CFBundleDisplayName = ${quote(target.name)};`;
}

export function xcodeProject(graph: Graph, root: string, compiler: string): Result<string, string> {
	let objects = "";
	let targets = "";
	let products = "";
	let sources = "";
	for (let i: int32 = 0; i < graph.targets.length; i += 1) {
		const target = graph.targets[i];
		if (target.platform != Platform.Macos) return Result.err("POC emitter supports macOS only: " + target.name);
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
		const script = "set -eu\ncd " + shellQuote(root) + "\nmkdir -p \"$TARGET_BUILD_DIR/" + target.name + ".app/Contents/MacOS\"\n" + shellQuote(compiler) + " build " + shellQuote(target.entry) + " --cc=clang --output=\"$TARGET_BUILD_DIR/$EXECUTABLE_PATH\"\n";
		objects += `${targetId} = { isa = PBXNativeTarget; name = ${quote(target.name)}; productName = ${quote(target.name)}; productType = "com.apple.product-type.application"; productReference = ${id(base + 1)}; buildConfigurationList = ${id(base + 2)}; buildPhases = (${id(base + 5)},); buildRules = (); dependencies = (${dependencies}); };\n`;
		objects += `${id(base + 1)} = { isa = PBXFileReference; explicitFileType = wrapper.application; path = ${quote(target.name + ".app")}; sourceTree = BUILT_PRODUCTS_DIR; };\n`;
		objects += `${id(base + 2)} = { isa = XCConfigurationList; buildConfigurations = (${id(base + 3)},${id(base + 4)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug; };\n`;
		objects += `${id(base + 3)} = { isa = XCBuildConfiguration; name = Debug; buildSettings = { ${buildSettings(target)} }; };\n`;
		objects += `${id(base + 4)} = { isa = XCBuildConfiguration; name = Release; buildSettings = { ${buildSettings(target)} }; };\n`;
		objects += `${id(base + 5)} = { isa = PBXShellScriptBuildPhase; buildActionMask = 2147483647; files = (); inputPaths = (); outputPaths = (); alwaysOutOfDate = 1; name = "Compile MetaScript"; runOnlyForDeploymentPostprocessing = 0; shellPath = /bin/sh; shellScript = ${quote(script)}; };\n`;
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
