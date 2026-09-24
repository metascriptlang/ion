import { Project, Target, Platform } from "../description";
import { bundlePrefix } from "../plugins";
import { resolve } from "../resolve";
import { gradleProject, GeneratedFile, nativeLibrary } from "../gradle";
import { xcodeProject } from "../xcode";
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
check(app.android.minSdk == 23 && app.android.compileSdk == 36 && app.android.targetSdk == 36, "SDK defaults");
check(app.android.ndkVersion == "28.0.13004108" && app.android.abi == "arm64-v8a", "NDK and ABI defaults");
check(app.android.javaVersion == 17, "Java default");
check(app.deploymentTarget == "", "Android minimum lives only in android.minSdk");

const first = render([app]);
check(first.ok, "Android graph emits a Gradle project");
const second = render([app]);
if (first.ok && second.ok) {
	check(JSON.stringify(first.value) == JSON.stringify(second.value), "deterministic output");
	const files = first.value;
	const paths: Vec<string> = [];
	for (const generated of files) paths.push(generated.path);
	check(paths.join(",") == [
		"settings.gradle",
		"build.gradle",
		"gradle.properties",
		"gradle/wrapper/gradle-wrapper.properties",
		"app/build.gradle",
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
	check(root.includes("compileSdk = 36") && root.includes("minSdk = 23") && root.includes("JavaVersion.VERSION_17"), "libraries use the target's levels");
	check(root.includes("tasks.withType(JavaCompile)") && root.includes("\"apk/${variant}\").deleteDir()"), "library javac drops the variant's packages");
	const wrapper = file(files, "gradle/wrapper/gradle-wrapper.properties");
	check(wrapper.includes("gradle-9.3.1-bin.zip"), "Gradle pinned");
	check(wrapper.includes("distributionSha256Sum=b266d5ff6b90eada6dc3b20cb090e3731302e553a27c5d3e4df1f0d76beaff06"), "Gradle checksum pinned");

	const build = file(files, "app/build.gradle");
	check(build.includes("namespace = 'dev.metascript.app'"), "package-stable namespace");
	check(build.includes("applicationId = 'dev.ion.Mobile'"), "bundle identity is applicationId");
	check(build.includes("minSdk = 23") && build.includes("targetSdk = 36") && build.includes("compileSdk = 36"), "SDK levels");
	check(build.includes("ndkVersion = '28.0.13004108'") && build.includes("abiFilters 'arm64-v8a'"), "NDK and ABI");
	check(build.includes("JavaVersion.VERSION_17"), "Java level");
	check(build.includes("def mscCompiler = '/compiler\\'s path/msc'"), "compiler pinned and quoted");
	check(build.includes("def mscEntry = '/source with spaces/main.ms'"), "entry pinned");
	check(build.includes("'--os=android', '--cpu=arm64', '--app=lib'"), "msc shared-library target");
	check(build.includes("aarch64-linux-android${minSdk.get()}-clang"), "API-specific clang wrapper");
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
	check(!build.includes("externalNativeBuild") && !build.includes("CMake") && !build.includes(".c'"), "no native source inventory");

	const manifest = file(files, "app/src/main/AndroidManifest.xml");
	check(manifest.includes("android:name=\"dev.metascript.app.MainActivity\""), "manifest names the bootstrap activity");
	check(manifest.includes("android:configChanges=\""), "size changes reach the running activity");
	check(file(files, "app/src/main/res/values/strings.xml").includes("<string name=\"app_name\">Mobile</string>"), "label");
	const native = file(files, "app/src/main/java/dev/metascript/app/NativeApp.java");
	check(native.includes("package dev.metascript.app;") && native.includes("System.loadLibrary(\"metascript\")"), "JNI class loads the stable library");
	for (const method of ["start(FrameLayout root)", "resize(int width, int height)", "pause()", "resume()", "destroy()"]) {
		check(native.includes("static native void " + method + ";"), "JNI method " + method);
	}
	const activity = file(files, "app/src/main/java/dev/metascript/app/MainActivity.java");
	check(activity.includes("new FrameLayout(this)") && activity.includes("NativeApp.start(root)"), "activity creates the root");
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
expectError([{ ...app, android: { ...app.android, targetSdk: 22 } }], "Android target 'Mobile' needs minSdk <= targetSdk <= compileSdk, got 23 <= 22 <= 36");
expectError([{ ...app, android: { ...app.android, compileSdk: 35 } }], "Android target 'Mobile' needs minSdk <= targetSdk <= compileSdk, got 23 <= 36 <= 35");
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
console.log("android: " + passed.toString() + " assertions passed");
