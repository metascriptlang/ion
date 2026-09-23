import { Graph, Target, Platform } from "./description";

export struct GeneratedFile {
	path: string;
	content: string;
}

export const nativeLibrary = "metascript";
export const wrapperFiles: Vec<string> = ["gradlew", "gradlew.bat", "gradle/wrapper/gradle-wrapper.jar"];

const bootstrapPackage = "dev.metascript.app";
const bootstrapPath = "app/src/main/java/dev/metascript/app/";

function groovy(value: string): string {
	return "'" + value.replaceAll("\\", "\\\\").replaceAll("'", "\\'") + "'";
}

function xml(value: string): string {
	return value.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;")
		.replaceAll("\"", "&quot;").replaceAll("'", "\\'");
}

function lines(values: Vec<string>): string {
	return values.join("\n") + "\n";
}

function numeric(value: string): boolean {
	if (value == "") return false;
	for (let i = 0; i < value.byteLength; i += 1) {
		const c = value.byteAt(i);
		if (c < 48 || c > 57) return false;
	}
	return true;
}

function validApplicationId(value: string): boolean {
	const segments = value.split(".");
	if (segments.length < 2) return false;
	for (const segment of segments) {
		if (segment == "") return false;
		for (let i = 0; i < segment.byteLength; i += 1) {
			const c = segment.byteAt(i);
			const letter = (c >= 65 && c <= 90) || (c >= 97 && c <= 122);
			if (letter || (i > 0 && ((c >= 48 && c <= 57) || c == 95))) continue;
			return false;
		}
	}
	return true;
}

function validate(target: Target): Result<void, string> {
	const name = "Android target '" + target.name + "'";
	const settings = target.android;
	if (target.deploymentTarget != "") {
		return Result.err(name + " sets deploymentTarget '" + target.deploymentTarget + "'; set android.minSdk instead");
	}
	if (settings.minSdk < 23) return Result.err(name + " needs minSdk >= 23, got " + settings.minSdk.toString());
	if (settings.targetSdk < settings.minSdk || settings.compileSdk < settings.targetSdk) {
		return Result.err(
			name + " needs minSdk <= targetSdk <= compileSdk, got " + settings.minSdk.toString() + " <= " +
			settings.targetSdk.toString() + " <= " + settings.compileSdk.toString(),
		);
	}
	if (settings.abi != "arm64-v8a") return Result.err(name + " has unsupported ABI '" + settings.abi + "' (supported: arm64-v8a)");
	const ndk = settings.ndkVersion.split(".");
	if (ndk.length != 3 || !numeric(ndk[0]) || !numeric(ndk[1]) || !numeric(ndk[2])) {
		return Result.err(name + " has malformed ndkVersion '" + settings.ndkVersion + "' (expected major.minor.build)");
	}
	if (parseInt(ndk[0]) < 28) {
		return Result.err(name + " needs NDK 28 or newer for 16 KiB page alignment, got '" + settings.ndkVersion + "'");
	}
	if (settings.javaVersion < 17) return Result.err(name + " needs Java 17 or newer, got " + settings.javaVersion.toString());
	if (!validApplicationId(target.bundleId)) return Result.err(name + " has invalid applicationId '" + target.bundleId + "'");
	return Result.ok(null);
}

function settingsGradle(name: string): string {
	return lines([
		"pluginManagement {",
		"\trepositories {",
		"\t\tgoogle()",
		"\t\tmavenCentral()",
		"\t\tgradlePluginPortal()",
		"\t}",
		"}",
		"",
		"dependencyResolutionManagement {",
		"\trepositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)",
		"\trepositories {",
		"\t\tgoogle()",
		"\t\tmavenCentral()",
		"\t}",
		"}",
		"",
		"rootProject.name = " + groovy(name),
		"include(':app')",
	]);
}

function appGradle(target: Target, root: string, compiler: string): string {
	const settings = target.android;
	const java = "JavaVersion.VERSION_" + settings.javaVersion.toString();
	return lines([
		"import javax.inject.Inject",
		"",
		"plugins {",
		"\tid 'com.android.application'",
		"}",
		"",
		"def mscCompiler = " + groovy(compiler),
		"def mscEntry = " + groovy(root + "/" + target.entry),
		"def mscMinSdk = " + settings.minSdk.toString(),
		"",
		"abstract class MetaScriptLibrary extends DefaultTask {",
		"\t@Input abstract Property<String> getCompiler()",
		"\t@Input abstract Property<String> getEntry()",
		"\t@Input abstract Property<Integer> getMinSdk()",
		"\t@Input abstract Property<Boolean> getRelease()",
		"\t@Internal abstract DirectoryProperty getNdkDirectory()",
		"\t@Internal abstract DirectoryProperty getWorkDirectory()",
		"\t@OutputDirectory abstract DirectoryProperty getOutputDirectory()",
		"\t@Internal abstract ConfigurableFileCollection getPackagedOutputs()",
		"\t@Inject abstract ExecOperations getExecOperations()",
		"",
		"\t@TaskAction",
		"\tvoid compile() {",
		"\t\tFile output = outputDirectory.get().asFile",
		"\t\toutput.deleteDir()",
		"\t\tFile abi = new File(output, 'arm64-v8a')",
		"\t\tFile work = workDirectory.get().asFile",
		"\t\tif (!abi.mkdirs() || !(work.isDirectory() || work.mkdirs())) throw new GradleException(\"MetaScript: cannot create ${abi} and ${work}\")",
		"\t\tString os = System.getProperty('os.name').toLowerCase()",
		"\t\tString host = os.contains('mac') ? 'darwin-x86_64' : os.contains('linux') ? 'linux-x86_64' : null",
		"\t\tif (host == null) throw new GradleException(\"MetaScript: unsupported Android build host: ${os}\")",
		"\t\tFile clang = ndkDirectory.get().file(\"toolchains/llvm/prebuilt/${host}/bin/aarch64-linux-android${minSdk.get()}-clang\").asFile",
		"\t\tif (!clang.isFile()) throw new GradleException(\"MetaScript: NDK clang wrapper does not exist: ${clang}\")",
		"\t\tList<String> command = [compiler.get(), 'build', entry.get(), '--os=android', '--cpu=arm64', '--app=lib',",
		"\t\t\t\"--cc=${clang}\".toString(), \"--output=${new File(abi, 'lib" + nativeLibrary + ".so')}\".toString(), '--no-color']",
		"\t\tif (release.get()) command += ['--release', '--strip']",
		"\t\ttry {",
		"\t\t\texecOperations.exec {",
		"\t\t\t\tworkingDir(work)",
		"\t\t\t\tcommandLine(command)",
		"\t\t\t}",
		"\t\t} catch (Exception failure) {",
		"\t\t\toutput.deleteDir()",
		"\t\t\tpackagedOutputs.files.each { it.deleteDir() }",
		"\t\t\tthrow failure",
		"\t\t}",
		"\t}",
		"}",
		"",
		"def signingInputs = [",
		"\tstoreFile: ['ion.android.storeFile', 'ION_ANDROID_STORE_FILE'],",
		"\tstorePassword: ['ion.android.storePassword', 'ION_ANDROID_STORE_PASSWORD'],",
		"\tkeyAlias: ['ion.android.keyAlias', 'ION_ANDROID_KEY_ALIAS'],",
		"\tkeyPassword: ['ion.android.keyPassword', 'ION_ANDROID_KEY_PASSWORD'],",
		"]",
		"def signing = signingInputs.collectEntries { key, names ->",
		"\t[key, providers.gradleProperty(names[0]).orElse(providers.environmentVariable(names[1])).getOrNull()]",
		"}",
		"def missingSigning = signingInputs.findAll { key, names -> !signing[key] }.collect { key, names -> \"${names[1]} (or -P${names[0]})\".toString() }",
		"",
		"android {",
		"\tnamespace = '" + bootstrapPackage + "'",
		"\tcompileSdk = " + settings.compileSdk.toString(),
		"\tndkVersion = " + groovy(settings.ndkVersion),
		"",
		"\tdefaultConfig {",
		"\t\tapplicationId = " + groovy(target.bundleId),
		"\t\tminSdk = " + settings.minSdk.toString(),
		"\t\ttargetSdk = " + settings.targetSdk.toString(),
		"\t\tversionCode = 1",
		"\t\tversionName = '1.0'",
		"\t\tndk {",
		"\t\t\tabiFilters " + groovy(settings.abi),
		"\t\t}",
		"\t}",
		"",
		"\tsigningConfigs {",
		"\t\trelease {",
		"\t\t\tif (missingSigning.isEmpty()) {",
		"\t\t\t\tstoreFile = file(signing.storeFile)",
		"\t\t\t\tstorePassword = signing.storePassword",
		"\t\t\t\tkeyAlias = signing.keyAlias",
		"\t\t\t\tkeyPassword = signing.keyPassword",
		"\t\t\t}",
		"\t\t}",
		"\t}",
		"",
		"\tbuildTypes {",
		"\t\trelease {",
		"\t\t\tminifyEnabled = true",
		"\t\t\tproguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'",
		"\t\t\tsigningConfig = signingConfigs.release",
		"\t\t}",
		"\t}",
		"",
		"\tcompileOptions {",
		"\t\tsourceCompatibility = " + java,
		"\t\ttargetCompatibility = " + java,
		"\t}",
		"}",
		"",
		"tasks.register('verifyReleaseSigning') {",
		"\tdoLast {",
		"\t\tif (!missingSigning.isEmpty()) throw new GradleException(\"Release signing is missing ${missingSigning.join(', ')}\")",
		"\t}",
		"}",
		"tasks.matching { it.name == 'preReleaseBuild' }.configureEach { dependsOn 'verifyReleaseSigning' }",
		"",
		"androidComponents {",
		"\tonVariants(selector().all()) { variant ->",
		"\t\tdef library = tasks.register(\"compileMetaScript${variant.name.capitalize()}\", MetaScriptLibrary) {",
		"\t\t\tcompiler = mscCompiler",
		"\t\t\tentry = mscEntry",
		"\t\t\tminSdk = mscMinSdk",
		"\t\t\trelease = variant.buildType == 'release'",
		"\t\t\tndkDirectory = androidComponents.sdkComponents.ndkDirectory",
		"\t\t\tworkDirectory = layout.buildDirectory.dir(\"metascript/${variant.name}\")",
		"\t\t\tpackagedOutputs.from(layout.buildDirectory.dir(\"outputs/apk/${variant.name}\"), layout.buildDirectory.dir(\"outputs/bundle/${variant.name}\"))",
		"\t\t\toutputs.upToDateWhen { false }",
		"\t\t\tif (variant.buildType == 'release') dependsOn('verifyReleaseSigning')",
		"\t\t}",
		"\t\tvariant.sources.jniLibs.addGeneratedSourceDirectory(library) { it.outputDirectory }",
		"\t}",
		"}",
	]);
}

function manifest(): string {
	return lines([
		"<?xml version=\"1.0\" encoding=\"utf-8\"?>",
		"<manifest xmlns:android=\"http://schemas.android.com/apk/res/android\">",
		"\t<application",
		"\t\tandroid:allowBackup=\"false\"",
		"\t\tandroid:label=\"@string/app_name\"",
		"\t\tandroid:theme=\"@android:style/Theme.Material.Light.NoActionBar\">",
		"\t\t<activity",
		"\t\t\tandroid:name=\"" + bootstrapPackage + ".MainActivity\"",
		"\t\t\tandroid:configChanges=\"orientation|screenSize|screenLayout|smallestScreenSize|density|keyboard|keyboardHidden|navigation|uiMode\"",
		"\t\t\tandroid:exported=\"true\">",
		"\t\t\t<intent-filter>",
		"\t\t\t\t<action android:name=\"android.intent.action.MAIN\" />",
		"\t\t\t\t<category android:name=\"android.intent.category.LAUNCHER\" />",
		"\t\t\t</intent-filter>",
		"\t\t</activity>",
		"\t</application>",
		"</manifest>",
	]);
}

function mainActivity(): string {
	return lines([
		"package " + bootstrapPackage + ";",
		"",
		"import android.app.Activity;",
		"import android.os.Bundle;",
		"import android.widget.FrameLayout;",
		"",
		"public final class MainActivity extends Activity {",
		"\t@Override",
		"\tprotected void onCreate(Bundle state) {",
		"\t\tsuper.onCreate(state);",
		"\t\tFrameLayout root = new FrameLayout(this);",
		"\t\tsetContentView(root);",
		"\t\tNativeApp.start(root);",
		"\t\troot.addOnLayoutChangeListener((view, left, top, right, bottom, oldLeft, oldTop, oldRight, oldBottom) -> {",
		"\t\t\tif (right - left != oldRight - oldLeft || bottom - top != oldBottom - oldTop) {",
		"\t\t\t\tNativeApp.resize(right - left, bottom - top);",
		"\t\t\t}",
		"\t\t});",
		"\t}",
		"",
		"\t@Override",
		"\tprotected void onResume() {",
		"\t\tsuper.onResume();",
		"\t\tNativeApp.resume();",
		"\t}",
		"",
		"\t@Override",
		"\tprotected void onPause() {",
		"\t\tNativeApp.pause();",
		"\t\tsuper.onPause();",
		"\t}",
		"",
		"\t@Override",
		"\tprotected void onDestroy() {",
		"\t\tNativeApp.destroy();",
		"\t\tsuper.onDestroy();",
		"\t}",
		"}",
	]);
}

function nativeApp(): string {
	return lines([
		"package " + bootstrapPackage + ";",
		"",
		"import android.widget.FrameLayout;",
		"",
		"public final class NativeApp {",
		"\tstatic {",
		"\t\tSystem.loadLibrary(\"" + nativeLibrary + "\");",
		"\t}",
		"",
		"\tstatic native void start(FrameLayout root);",
		"\tstatic native void resize(int width, int height);",
		"\tstatic native void pause();",
		"\tstatic native void resume();",
		"\tstatic native void destroy();",
		"",
		"\tprivate NativeApp() {}",
		"}",
	]);
}

export function gradleProject(graph: Graph, root: string, compiler: string): Result<Vec<GeneratedFile>, string> {
	for (const target of graph.targets) {
		if (target.platform == Platform.Android) continue;
		const platform = target.platform == Platform.Ios ? "iOS" : "macOS";
		return Result.err("Android project cannot contain the " + platform + " target '" + target.name + "'");
	}
	if (graph.targets.length != 1) {
		const names: Vec<string> = [];
		for (const target of graph.targets) names.push(target.name);
		return Result.err(
			"Android project holds exactly one application target; got " + graph.targets.length.toString() + ": " + names.join(", "),
		);
	}
	const target = graph.targets[0];
	try validate(target);
	return Result.ok([
		{ path: "settings.gradle", content: settingsGradle(graph.name) },
		{ path: "build.gradle", content: lines(["plugins {", "\tid 'com.android.application' version '9.1.0' apply false", "}"]) },
		{ path: "gradle.properties", content: lines(["org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8"]) },
		{
			path: "gradle/wrapper/gradle-wrapper.properties",
			content: lines([
				"distributionBase=GRADLE_USER_HOME",
				"distributionPath=wrapper/dists",
				"distributionUrl=https\\://services.gradle.org/distributions/gradle-9.3.1-bin.zip",
				"distributionSha256Sum=b266d5ff6b90eada6dc3b20cb090e3731302e553a27c5d3e4df1f0d76beaff06",
				"networkTimeout=10000",
				"validateDistributionUrl=true",
				"zipStoreBase=GRADLE_USER_HOME",
				"zipStorePath=wrapper/dists",
			]),
		},
		{ path: "app/build.gradle", content: appGradle(target, root, compiler) },
		{ path: "app/proguard-rules.pro", content: lines(["-keep class " + bootstrapPackage + ".NativeApp { native <methods>; }"]) },
		{ path: "app/src/main/AndroidManifest.xml", content: manifest() },
		{
			path: "app/src/main/res/values/strings.xml",
			content: lines(["<?xml version=\"1.0\" encoding=\"utf-8\"?>", "<resources>", "\t<string name=\"app_name\">" + xml(target.name) + "</string>", "</resources>"]),
		},
		{ path: bootstrapPath + "MainActivity.java", content: mainActivity() },
		{ path: bootstrapPath + "NativeApp.java", content: nativeApp() },
	]);
}
