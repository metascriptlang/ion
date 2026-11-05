import { Project, Target, Platform, StatusBarStyle, plistBoolean, plistString } from "../description";
import { bundlePrefix } from "../plugins";
import { resolve } from "../resolve";
import { gradleProject, GeneratedFile, nativeLibrary } from "../gradle";
import { xcodeProject } from "../xcode";
import { render as renderProjects } from "../generate";
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
	return gradleProject(graph.value, "/source with spaces", "/compiler's path/msc");
}

function render(targets: Vec<Target>): Result<Vec<GeneratedFile>, string> {
	return emit({ name: "Mobile", targets, plugins: [bundlePrefix("dev.ion")] });
}

function expectRendered(rendered: Result<Vec<GeneratedFile>, string>, message: string): void {
	if (rendered.ok) {
		check(false, "expected error: " + message);
	} else {
		check(rendered.error == message, message + " (got: " + rendered.error + ")");
	}
}

function expectError(targets: Vec<Target>, message: string): void {
	expectRendered(render(targets), message);
}

function file(files: Vec<GeneratedFile>, path: string): string {
	for (const generated of files) {
		if (generated.path == path) return generated.content;
	}
	check(false, "missing generated file " + path);
	return "";
}

const app = Target.androidApp("Mobile", "main.ms");
check(app.platform == Platform.Android, "androidApp selects Android");
check(app.android.minSdk == 24 && app.android.compileSdk == 36 && app.android.targetSdk == 36, "SDK defaults");
check(app.android.ndkVersion == "28.0.13004108" && app.android.abi == "arm64-v8a", "NDK and ABI defaults");
check(app.android.javaVersion == 17, "Java default");
check(app.android.permissions.length == 0, "no declared permission by default");
check(app.deploymentTarget == "", "Android minimum lives only in android.minSdk");

const first = render([app]);
check(first.ok, "Android graph emits a Gradle project");
const second = render([app]);
if (first.ok && second.ok) {
	check(JSON.stringify(first.value) == JSON.stringify(second.value), "deterministic output");
	const files = first.value;
	let paths: Vec<string> = [];
	for (const generated of files) paths.push(generated.path);
	check(paths.join(",") == [
		"settings.gradle",
		"build.gradle",
		"gradle.properties",
		"gradle/wrapper/gradle-wrapper.properties",
		"app/build.gradle",
		"app/ionAssets.c",
		"app/proguard-rules.pro",
		"app/src/main/AndroidManifest.xml",
		"app/src/main/res/values/strings.xml",
		"app/src/main/java/dev/metascript/app/MainActivity.java",
		"app/src/main/java/dev/metascript/app/NativeApp.java",
	].join(","), "emitted file set: " + paths.join(","));
	check(nativeLibrary == "metascript", "stable native library name");

	const settings = file(files, "settings.gradle");
	check(settings.includes("rootProject.name = 'Mobile'") && settings.includes("include(':app')"), "settings names the project");
	check(settings.includes("def mscEntry = '/source with spaces/main.ms'"), "settings pins the entry");
	check(
		settings.includes("'check', mscEntry, '--os=android', '--cpu=arm64', \"-d:ionAndroidLibraries=${androidLibraries}\""),
		"settings reads the declared Android libraries from msc check",
	);
	check(settings.includes("androidLibraries.delete()"), "each configuration starts from no declaration");
	check(settings.includes("throw new GradleException(\"MetaScript: msc check failed"), "a failed check fails configuration");
	check(settings.includes("project(name).projectDir = new File(path)"), "a declared library is built in place");
	const root = file(files, "build.gradle");
	check(root.includes("id 'com.android.application' version '9.1.0' apply false"), "AGP pinned");
	check(root.includes("id 'com.android.library' version '9.1.0' apply false"), "library plugin pinned with the application");
	check(root.includes("rootProject.layout.buildDirectory.dir(\"androidLibraries/${name}\")"), "library build output stays in the project");
	check(root.includes("compileSdk = 36") && root.includes("minSdk = 24") && root.includes("JavaVersion.VERSION_17"), "libraries use the target's levels");
	check(root.includes("tasks.withType(JavaCompile)") && root.includes("\"apk/${variant}\").deleteDir()"), "library javac drops the variant's packages");
	const wrapper = file(files, "gradle/wrapper/gradle-wrapper.properties");
	check(wrapper.includes("gradle-9.3.1-bin.zip"), "Gradle pinned");
	check(wrapper.includes("distributionSha256Sum=b266d5ff6b90eada6dc3b20cb090e3731302e553a27c5d3e4df1f0d76beaff06"), "Gradle checksum pinned");

	const build = file(files, "app/build.gradle");
	check(build.includes("namespace = 'dev.metascript.app'"), "package-stable namespace");
	check(build.includes("applicationId = 'dev.ion.Mobile'"), "bundle identity is applicationId");
	check(build.includes("minSdk = 24") && build.includes("targetSdk = 36") && build.includes("compileSdk = 36"), "SDK levels");
	check(build.includes("ndkVersion = '28.0.13004108'") && build.includes("abiFilters 'arm64-v8a'"), "NDK and ABI");
	check(build.includes("JavaVersion.VERSION_17"), "Java level");
	check(build.includes("def mscCompiler = '/compiler\\'s path/msc'"), "compiler pinned and quoted");
	check(build.includes("def mscEntry = '/source with spaces/main.ms'"), "entry pinned");
	check(build.includes("'--os=android', '--cpu=arm64', '--app=lib'"), "msc shared-library target");
	check(build.includes("aarch64-linux-android${minSdk.get()}-clang"), "API-specific clang wrapper");
	check(build.includes("os.contains('windows') ? 'windows-x86_64'") && build.includes("name.endsWith('-clang') ? '.cmd' : '.exe'"), "Windows NDK tools resolve to their .cmd and .exe launchers");
	check(build.includes("addGeneratedSourceDirectory"), "native output is a generated jniLibs source");
	check(build.includes("upToDateWhen { false }"), "msc owns incremental identity");
	check(build.includes("ION_ANDROID_STORE_FILE") && build.includes("verifyReleaseSigning"), "release signing surface");
	check(build.includes("if (variant.buildType == 'release') dependsOn('verifyReleaseSigning')"), "signing refused before native release work");
	check(build.includes("packagedOutputs.files.each { it.deleteDir() }"), "failed native build removes packaged variant output");
	check(build.includes("gradle.androidLibraries.each { implementation project(it) }"), "app depends on every declared library");
	check(build.includes("mapping = variant.artifacts.get(SingleArtifact.OBFUSCATION_MAPPING_FILE.INSTANCE)"), "Release checks R8's mapping");
	check(build.includes("R8 removed ${owner}, but ${implemented}"), "a removed JNI class fails the build");
	check(build.includes("tasks.matching { it.name in packaging }.configureEach { dependsOn nativeClasses }"), "packaging waits on the JNI class check");
	check(build.includes("layout.buildDirectory.dir(\"metascript/${variant.name}\")"), "per-variant msc work directory");
	check(!build.includes("externalNativeBuild") && !build.includes("CMake") && !build.replaceAll("'ionAssets.c'", "").includes(".c'"), "no native source inventory beyond the generated asset hand-off");

	const manifest = file(files, "app/src/main/AndroidManifest.xml");
	check(manifest.includes("android:name=\"dev.metascript.app.MainActivity\""), "manifest names the bootstrap activity");
	check(manifest.includes("android:configChanges=\""), "size changes reach the running activity");
	check(manifest.includes("android:launchMode=\"singleTask\""), "a new intent reaches the running activity");
	check(manifest.includes("<uses-permission android:name=\"android.permission.INTERNET\" />"), "the app may open network connections");
	check(manifest.split("<uses-permission ").length == 2, "no permission beyond INTERNET by default");
	check(manifest.includes("\t\tandroid:supportsRtl=\"true\"\n"), "the application follows a right-to-left locale");
	check(file(files, "app/src/main/res/values/strings.xml").includes("<string name=\"app_name\">Mobile</string>"), "label");
	const native = file(files, "app/src/main/java/dev/metascript/app/NativeApp.java");
	check(native.includes("package dev.metascript.app;") && native.includes("System.loadLibrary(\"metascript\")"), "JNI class loads the stable library");
	for (const method of ["start(FrameLayout root)", "resize(int width, int height)", "pause()", "resume()", "destroy()", "newIntent(Intent intent)",
		"permissionsResult(int requestCode, String[] permissions, int[] grantResults)", "activityResult(int requestCode, int resultCode, Intent data)"]) {
		check(native.includes("static native void " + method + ";"), "JNI method " + method);
	}
	const activity = file(files, "app/src/main/java/dev/metascript/app/MainActivity.java");
	check(activity.includes("new FrameLayout(this)") && activity.includes("NativeApp.start(root)"), "activity creates the root");
	check(activity.includes("NativeApp.newIntent(intent);"), "activity forwards a new intent");
	check(activity.includes("public final class MainActivity extends Activity {"), "the activity stays a platform Activity");
	check(activity.includes("\tpublic void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {\n\t\tsuper.onRequestPermissionsResult(requestCode, permissions, grantResults);\n\t\tNativeApp.permissionsResult(requestCode, permissions, grantResults);\n"), "activity forwards a permission result");
	check(activity.includes("\tprotected void onActivityResult(int requestCode, int resultCode, Intent data) {\n\t\tsuper.onActivityResult(requestCode, resultCode, data);\n\t\tNativeApp.activityResult(requestCode, resultCode, data);\n"), "activity forwards an activity result");
	check(activity.includes("root.setFocusableInTouchMode(true);") && activity.includes("root.setDescendantFocusability(ViewGroup.FOCUS_BEFORE_DESCENDANTS);"), "a blurred field hands focus to the root");
	check(file(files, "app/proguard-rules.pro").includes("-keep class dev.metascript.app.NativeApp"), "R8 keeps the JNI class");
}

const android = resolve({ name: "Mobile", targets: [app], plugins: [bundlePrefix("dev.ion")] });
if (android.ok) {
	const xcode = xcodeProject(android.value, "/source", "/compiler");
	check(!xcode.ok && xcode.error == "Xcode project cannot contain the Android target 'Mobile'", "Xcode refuses Android targets");
}
expectError([app, { ...app, name: "Other" }], "Android project holds exactly one application target; got 2: Mobile, Other");
expectError([app, Target.iosApp("Other", "main.ms")], "Android project cannot contain the iOS target 'Other'");
expectError([Target.iosApp("Mobile", "main.ms")], "Android project cannot contain the iOS target 'Mobile'");
expectError([{ ...app, deploymentTarget: "23.0" }], "Android target 'Mobile' sets deploymentTarget '23.0'; set android.minSdk instead");
expectError([{ ...app, android: { ...app.android, minSdk: 21 } }], "Android target 'Mobile' needs minSdk >= 23, got 21");
expectError([{ ...app, android: { ...app.android, targetSdk: 22 } }], "Android target 'Mobile' needs minSdk <= targetSdk <= compileSdk, got 24 <= 22 <= 36");
expectError([{ ...app, android: { ...app.android, compileSdk: 35 } }], "Android target 'Mobile' needs minSdk <= targetSdk <= compileSdk, got 24 <= 36 <= 35");
expectError([{ ...app, android: { ...app.android, abi: "x86_64" } }], "Android target 'Mobile' has unsupported ABI 'x86_64' (supported: arm64-v8a)");
expectError([{ ...app, android: { ...app.android, ndkVersion: "27.1.12297006" } }],
	"Android target 'Mobile' needs NDK 28 or newer for 16 KiB page alignment, got '27.1.12297006'");
expectError([{ ...app, android: { ...app.android, ndkVersion: "28" } }], "Android target 'Mobile' has malformed ndkVersion '28' (expected major.minor.build)");
expectError([{ ...app, android: { ...app.android, javaVersion: 11 } }], "Android target 'Mobile' needs Java 17 or newer, got 11");
for (const id of ["Mobile", "dev.1ion.Mobile", "dev..Mobile", "dev.ion-x.Mobile"]) {
	expectRendered(
		emit({ name: "Mobile", targets: [{ ...app, bundleId: id }], plugins: [] }),
		"Android target 'Mobile' has invalid applicationId '" + id + "'",
	);
}
function mixedProject(): void {
	const graph = resolve({ name: "Mobile", targets: [app, Target.iosApp("Tablet", "main.ms")], plugins: [bundlePrefix("dev.ion")] });
	if (!graph.ok) {
		check(false, "one project describes an Android and an iOS target: " + graph.error);
		return;
	}
	const rendered = renderProjects(graph.value, "/source", "/msc", "tooling/generator");
	if (!rendered.ok) {
		check(false, "an Android and an iOS target render together: " + rendered.error);
		return;
	}
	let paths: Vec<string> = [];
	for (const generated of rendered.value) paths.push(generated.path);
	for (const expected of ["Mobile.xcodeproj/project.pbxproj", "IonMain.m", "app/src/main/AndroidManifest.xml", "settings.gradle"]) {
		check(paths.includes(expected), "the mixed project writes " + expected);
	}
	check(!file(rendered.value, "Mobile.xcodeproj/project.pbxproj").includes("Android"), "the Xcode project leaves the Android target out");
	check(!paths.includes("Tablet-Info.plist"), "a target without Info.plist keys writes no plist");
}

function infoPlistKeys(): void {
	const tablet: Target = { ...Target.iosApp("Tablet", "main.ms"), infoPlist: [plistBoolean("UIFileSharingEnabled", true), plistString("NSCameraUsageDescription", "Scan <codes> & more")] };
	const graph = resolve({ name: "Mobile", targets: [tablet], plugins: [bundlePrefix("dev.ion")] });
	if (!graph.ok) {
		check(false, "a target with Info.plist keys resolves: " + graph.error);
		return;
	}
	const rendered = renderProjects(graph.value, "/source", "/msc", "tooling/generator");
	if (!rendered.ok) {
		check(false, "a target with Info.plist keys renders: " + rendered.error);
		return;
	}
	const plist = file(rendered.value, "Tablet-Info.plist");
	check(plist.includes("<key>UIFileSharingEnabled</key>\n\t<true/>"), "a boolean key is written as <true/>");
	check(plist.includes("<string>Scan &lt;codes&gt; &amp; more</string>"), "a string value is escaped");
	check(file(rendered.value, "Mobile.xcodeproj/project.pbxproj").includes("INFOPLIST_FILE = \"Tablet-Info.plist\"; "), "the target names its plist");
	const twice = resolve({ name: "Mobile", targets: [{ ...tablet, infoPlist: [plistBoolean("A", true), plistBoolean("A", false)] }], plugins: [bundlePrefix("dev.ion")] });
	if (!twice.ok) {
		check(false, "a duplicate key resolves: " + twice.error);
		return;
	}
	const refused = renderProjects(twice.value, "/source", "/msc", "tooling/generator");
	check(!refused.ok && refused.error == "target 'Tablet' sets Info.plist key 'A' twice", "a key set twice is refused");
}
infoPlistKeys();
function statusBarDeclared(): void {
	const pbx = (target: Target): string => {
		const graph = resolve({ name: "Mobile", targets: [target], plugins: [bundlePrefix("dev.ion")] });
		if (!graph.ok) return "resolve: " + graph.error;
		const rendered = renderProjects(graph.value, "/source", "/msc", "tooling/generator");
		return rendered.ok ? file(rendered.value, "Mobile.xcodeproj/project.pbxproj") : "render: " + rendered.error;
	};
	const tablet = Target.iosApp("Tablet", "main.ms");
	const light = pbx({ ...tablet, statusBar: { style: StatusBarStyle.Light, hidden: true } });
	check(light.includes("-d:statusBarLight -d:statusBarHidden "), "a light, hidden status bar is built in as defines");
	check(light.includes("INFOPLIST_KEY_UIStatusBarStyle = UIStatusBarStyleLightContent; INFOPLIST_KEY_UIStatusBarHidden = YES; "), "and written to Info.plist for launch");
	const dark = pbx({ ...tablet, statusBar: { style: StatusBarStyle.Dark, hidden: false } });
	check(dark.includes("-d:statusBarDark ") && dark.includes("UIStatusBarStyleDarkContent") && !dark.includes("statusBarHidden"), "a dark status bar");
	const plain = pbx(tablet);
	check(!plain.includes("-d:statusBar") && !plain.includes("UIStatusBar"), "the default status bar adds nothing");
	const graph = resolve({ name: "Desk", targets: [{ ...Target.app("Desk", "main.ms"), statusBar: { style: StatusBarStyle.Light, hidden: false } }], plugins: [bundlePrefix("dev.ion")] });
	check(!graph.ok && graph.error == "statusBar of 'Desk' applies to iOS targets only", "a macOS status bar is refused" + (graph.ok ? "" : ": " + graph.error));
}
statusBarDeclared();
function urlSchemesDeclared(): void {
	const rendered = (target: Target): Result<Vec<GeneratedFile>, string> => {
		const graph = resolve({ name: "Mobile", targets: [target], plugins: [bundlePrefix("dev.ion")] });
		if (!graph.ok) return Result.err(graph.error);
		return renderProjects(graph.value, "/source", "/msc", "tooling/generator");
	};
	const tablet = rendered({ ...Target.iosApp("Tablet", "main.ms"), urlSchemes: ["neonnav", "neon-nav.v2"] });
	if (!tablet.ok) {
		check(false, "an iOS target with URL schemes renders: " + tablet.error);
		return;
	}
	check(file(tablet.value, "Tablet-Info.plist").includes("<key>CFBundleURLTypes</key>\n\t<array>\n\t\t<dict>\n\t\t\t<key>CFBundleURLName</key>\n\t\t\t<string>dev.ion.Tablet</string>\n\t\t\t<key>CFBundleURLSchemes</key>\n\t\t\t<array>\n\t\t\t\t<string>neonnav</string>\n\t\t\t\t<string>neon-nav.v2</string>\n"), "URL schemes become one CFBundleURLTypes entry");
	check(file(tablet.value, "Mobile.xcodeproj/project.pbxproj").includes("INFOPLIST_FILE = \"Tablet-Info.plist\"; "), "a target with URL schemes names its plist");
	const desk = rendered({ ...Target.app("Desk", "main.ms"), urlSchemes: ["desk"] });
	check(desk.ok && file(desk.value, "Desk-Info.plist").includes("<string>desk</string>"), "a macOS target declares its scheme too");
	const phone = rendered({ ...app, urlSchemes: ["neonnav"] });
	check(phone.ok && file(phone.value, "app/src/main/AndroidManifest.xml").includes("\t\t\t<intent-filter>\n\t\t\t\t<action android:name=\"android.intent.action.VIEW\" />\n\t\t\t\t<category android:name=\"android.intent.category.DEFAULT\" />\n\t\t\t\t<category android:name=\"android.intent.category.BROWSABLE\" />\n\t\t\t\t<data android:scheme=\"neonnav\" />\n\t\t\t</intent-filter>\n\t\t</activity>"), "an Android target gets a VIEW filter for its scheme");
	const plain = rendered(app);
	check(plain.ok && !file(plain.value, "app/src/main/AndroidManifest.xml").includes("BROWSABLE"), "no scheme, no VIEW filter");
	for (const bad of ["", "1nav", "nav://", "na v"]) {
		const refused = rendered({ ...Target.iosApp("Tablet", "main.ms"), urlSchemes: [bad] });
		check(!refused.ok && refused.error == "invalid URL scheme for 'Tablet': '" + bad + "'", "scheme '" + bad + "' is refused");
	}
	const twice = rendered({ ...Target.iosApp("Tablet", "main.ms"), urlSchemes: ["a", "a"] });
	check(!twice.ok && twice.error == "URL scheme 'a' of 'Tablet' is declared twice", "a scheme declared twice is refused");
	const windows = rendered({ ...Target.windowsApp("Win", "main.ms"), urlSchemes: ["win"] });
	check(!windows.ok && windows.error == "urlSchemes of 'Win' apply to macOS, iOS and Android targets only", "a Windows scheme is refused");
	const clash = rendered({ ...Target.iosApp("Tablet", "main.ms"), urlSchemes: ["a"], infoPlist: [plistString("CFBundleURLTypes", "x")] });
	check(!clash.ok && clash.error == "target 'Tablet' sets Info.plist key 'CFBundleURLTypes' twice", "a raw CFBundleURLTypes beside urlSchemes is refused");
}
urlSchemesDeclared();
function permissionsDeclared(): void {
	const declared = render([{ ...app, android: { ...app.android, permissions: ["android.permission.CAMERA", "android.permission.INTERNET", "com.example.permission.C2D_MESSAGE"] } }]);
	if (!declared.ok) {
		check(false, "an Android target with permissions renders: " + declared.error);
		return;
	}
	check(file(declared.value, "app/src/main/AndroidManifest.xml").includes(
		"<manifest xmlns:android=\"http://schemas.android.com/apk/res/android\">\n" +
		"\t<uses-permission android:name=\"android.permission.INTERNET\" />\n" +
		"\t<uses-permission android:name=\"android.permission.CAMERA\" />\n" +
		"\t<uses-permission android:name=\"com.example.permission.C2D_MESSAGE\" />\n" +
		"\t<application\n"), "declared permissions follow INTERNET, which is written once");
	for (const bad of ["CAMERA", "", "android.permission.", "android.permission.CAMERA\" />", "1android.permission.CAMERA"]) {
		expectError([{ ...app, android: { ...app.android, permissions: [bad] } }],
			"Android target 'Mobile' has invalid permission '" + bad + "' (expected a full name such as android.permission.CAMERA)");
	}
	expectError([{ ...app, android: { ...app.android, permissions: ["android.permission.CAMERA", "android.permission.CAMERA"] } }],
		"Android target 'Mobile' declares permission 'android.permission.CAMERA' twice");
}
permissionsDeclared();
function swiftSourcesDeclared(): void {
	const rendered = (targets: Vec<Target>): Result<Vec<GeneratedFile>, string> => {
		const graph = resolve({ name: "Mobile", targets, plugins: [bundlePrefix("dev.ion")] });
		if (!graph.ok) return Result.err(graph.error);
		return renderProjects(graph.value, "/source", "/msc", "tooling/generator");
	};
	const tablet: Target = { ...Target.iosApp("Tablet", "main.ms"), swiftSources: ["native/value.swift"] };
	const built = rendered([tablet]);
	if (!built.ok) {
		check(false, "an iOS target with Swift sources renders: " + built.error);
		return;
	}
	const pbx = file(built.value, "Mobile.xcodeproj/project.pbxproj");
	check(pbx.includes("name = \"TabletSwift\"; productName = \"TabletSwift\"; productType = \"com.apple.product-type.library.static\";"), "the Swift sources become a static library target");
	check(pbx.includes("isa = PBXSourcesBuildPhase;") && pbx.includes("lastKnownFileType = sourcecode.swift; path = \"/source/native/value.swift\";"), "the library compiles the Swift file");
	check(pbx.includes("--link=$BUILT_PRODUCTS_DIR/libTabletSwift.a"), "msc links the library");
	check(pbx.includes("-L\\\\\\\"$SDKROOT/usr/lib/swift\\\\\\\""), "the Swift search paths are quoted for msc");
	check(pbx.includes("rm -f \\\"$BUILT_PRODUCTS_DIR/Tablet.app/Tablet\\\""), "a failed Swift build removes the app's executable first");
	const plain = rendered([Target.iosApp("Tablet", "main.ms")]);
	check(plain.ok && !file(plain.value, "Mobile.xcodeproj/project.pbxproj").includes("PBXSourcesBuildPhase"), "no Swift, no Sources phase");
	const desk = rendered([{ ...Target.app("Desk", "main.ms"), swiftSources: ["a.swift"] }]);
	check(!desk.ok && desk.error == "swiftSources of 'Desk' apply to iOS targets only", "a macOS target with Swift is refused");
	const header = rendered([{ ...tablet, swiftSources: ["native/value.h"] }]);
	check(!header.ok && header.error == "Swift source of 'Tablet' must end in .swift: native/value.h", "a non-Swift source is refused");
	const clash = rendered([tablet, Target.iosApp("TabletSwift", "main.ms")]);
	check(!clash.ok && clash.error == "the Swift library of 'Tablet' would be named 'TabletSwift', which another target already is", "a target named like the Swift library is refused");
}
swiftSourcesDeclared();
mixedProject();
function androidAssets(): void {
	const graph = resolve({ name: "Mobile", targets: [{ ...app, assets: ["assets/font.ttf", "src"] }], plugins: [bundlePrefix("dev.ion")] });
	if (!graph.ok) {
		check(false, "an Android target with assets resolves: " + graph.error);
		return;
	}
	const rendered = gradleProject(graph.value, "/source", "/msc");
	if (!rendered.ok) {
		check(false, "an Android target with assets renders: " + rendered.error);
		return;
	}
	const gradle = file(rendered.value, "app/build.gradle");
	check(gradle.includes("def ionAssetPlacements = ['assets/font.ttf': '/source/assets/font.ttf', 'src': '/source/src']"), "the build lists every asset by destination");
	check(gradle.includes("variant.sources.assets.addGeneratedSourceDirectory(assets)"), "the copied assets are the variant's assets");
	check(gradle.includes("\"--link=${assetsObject}\".toString(), '--passL=-landroid'"), "the native library links the asset hand-off");
	check(file(rendered.value, "app/src/main/java/dev/metascript/app/MainActivity.java").includes("NativeApp.assets(getAssets());\n\t\tFrameLayout root"), "the activity hands its AssetManager over before start");
	check(file(rendered.value, "app/ionAssets.c").includes("Java_dev_metascript_app_NativeApp_assets(JNIEnv *env, jclass cls, jobject assets)"), "the generated C implements the native method");
}
androidAssets();
console.log("android: " + passed.toString() + " assertions passed");
