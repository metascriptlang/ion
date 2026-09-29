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

function settingsGradle(name: string, compiler: string, entry: string): string {
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
		"",
		"def mscCompiler = " + groovy(compiler),
		"def mscEntry = " + groovy(entry),
		"def androidLibraries = new File(settingsDir, 'build/metascript/androidLibraries.txt')",
		"def checkDirectory = new File(settingsDir, 'build/metascript/check')",
		"androidLibraries.delete()",
		"if (!(checkDirectory.isDirectory() || checkDirectory.mkdirs())) throw new GradleException(\"MetaScript: cannot create ${checkDirectory}\")",
		"def check = providers.exec {",
		"\tworkingDir(checkDirectory)",
		"\tcommandLine(mscCompiler, 'check', mscEntry, '--os=android', '--cpu=arm64', \"-d:ionAndroidLibraries=${androidLibraries}\", '--no-color')",
		"\tignoreExitValue = true",
		"}",
		"if (check.result.get().exitValue != 0) {",
		"\tthrow new GradleException(\"MetaScript: msc check failed\\n\" + check.standardOutput.asText.get() + check.standardError.asText.get())",
		"}",
		"gradle.ext.androidLibraries = []",
		"(androidLibraries.isFile() ? androidLibraries.readLines().unique().sort() : []).each { path ->",
		"\tString name = ':' + path.replaceAll('[^A-Za-z0-9]+', '-').replaceAll('^-|-$', '')",
		"\tif (gradle.androidLibraries.contains(name)) throw new GradleException(\"MetaScript: two Android libraries map to the Gradle project ${name}\")",
		"\tinclude(name)",
		"\tproject(name).projectDir = new File(path)",
		"\tgradle.androidLibraries << name",
		"}",
	]);
}

function rootGradle(target: Target): string {
	const settings = target.android;
	const java = "JavaVersion.VERSION_" + settings.javaVersion.toString();
	return lines([
		"plugins {",
		"\tid 'com.android.application' version '9.1.0' apply false",
		"\tid 'com.android.library' version '9.1.0' apply false",
		"}",
		"",
		"subprojects {",
		"\tif (path == ':app') return",
		"\tlayout.buildDirectory = rootProject.layout.buildDirectory.dir(\"androidLibraries/${name}\")",
		"\tFile packaged = project(':app').layout.buildDirectory.dir('outputs').get().asFile",
		"\ttasks.withType(JavaCompile).configureEach { compile ->",
		"\t\tString variant = compile.name.replaceFirst('^compile', '').replaceFirst('JavaWithJavac$', '').uncapitalize()",
		"\t\tcompile.doFirst {",
		"\t\t\tnew File(packaged, \"apk/${variant}\").deleteDir()",
		"\t\t\tnew File(packaged, \"bundle/${variant}\").deleteDir()",
		"\t\t}",
		"\t}",
		"\tplugins.withId('com.android.library') {",
		"\t\tandroid {",
		"\t\t\tcompileSdk = " + settings.compileSdk.toString(),
		"\t\t\tdefaultConfig {",
		"\t\t\t\tminSdk = " + settings.minSdk.toString(),
		"\t\t\t}",
		"\t\t\tcompileOptions {",
		"\t\t\t\tsourceCompatibility = " + java,
		"\t\t\t\ttargetCompatibility = " + java,
		"\t\t\t}",
		"\t\t}",
		"\t}",
		"}",
	]);
}

function appGradle(target: Target, root: string, compiler: string): string {
	const settings = target.android;
	const java = "JavaVersion.VERSION_" + settings.javaVersion.toString();
	return lines([
		"import com.android.build.api.artifact.SingleArtifact",
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
		"\tstatic String ndkHost() {",
		"\t\tString os = System.getProperty('os.name').toLowerCase()",
		"\t\tString host = os.contains('mac') ? 'darwin-x86_64' : os.contains('linux') ? 'linux-x86_64' : null",
		"\t\tif (host == null) throw new GradleException(\"MetaScript: unsupported Android build host: ${os}\")",
		"\t\treturn host",
		"\t}",
		"",
		"\t@TaskAction",
		"\tvoid compile() {",
		"\t\tFile output = outputDirectory.get().asFile",
		"\t\toutput.deleteDir()",
		"\t\tFile abi = new File(output, 'arm64-v8a')",
		"\t\tFile work = workDirectory.get().asFile",
		"\t\tif (!abi.mkdirs() || !(work.isDirectory() || work.mkdirs())) throw new GradleException(\"MetaScript: cannot create ${abi} and ${work}\")",
		"\t\tFile clang = ndkDirectory.get().file(\"toolchains/llvm/prebuilt/${ndkHost()}/bin/aarch64-linux-android${minSdk.get()}-clang\").asFile",
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
		"abstract class NativeClassCheck extends DefaultTask {",
		"\t@InputFile abstract RegularFileProperty getMapping()",
		"\t@InputDirectory abstract DirectoryProperty getLibraryDirectory()",
		"\t@Internal abstract DirectoryProperty getNdkDirectory()",
		"\t@Internal abstract ConfigurableFileCollection getPackagedOutputs()",
		"\t@Inject abstract ExecOperations getExecOperations()",
		"",
		"\tstatic String jniClass(String symbol) {",
		"\t\tString mangled = symbol.substring('Java_'.length())",
		"\t\tStringBuilder name = new StringBuilder()",
		"\t\tint i = 0",
		"\t\twhile (i < mangled.length()) {",
		"\t\t\tString next = mangled.substring(i + 1, Math.min(i + 2, mangled.length()))",
		"\t\t\tString after = mangled.substring(Math.min(i + 2, mangled.length()), Math.min(i + 3, mangled.length()))",
		"\t\t\tif (mangled.charAt(i) != '_' as char) {",
		"\t\t\t\tname.append(mangled.charAt(i))",
		"\t\t\t\ti += 1",
		"\t\t\t} else if (next == '1') {",
		"\t\t\t\tname.append('_')",
		"\t\t\t\ti += 2",
		"\t\t\t} else if (next == '0') {",
		"\t\t\t\tname.append((char) Integer.parseInt(mangled.substring(i + 2, i + 6), 16))",
		"\t\t\t\ti += 6",
		"\t\t\t} else if (next == '_' && after != '0' && after != '1') {",
		"\t\t\t\tbreak",
		"\t\t\t} else {",
		"\t\t\t\tname.append('.')",
		"\t\t\t\ti += 1",
		"\t\t\t}",
		"\t\t}",
		"\t\tString method = name.toString()",
		"\t\treturn method.substring(0, method.lastIndexOf('.'))",
		"\t}",
		"",
		"\t@TaskAction",
		"\tvoid verify() {",
		"\t\tFile nm = ndkDirectory.get().file(\"toolchains/llvm/prebuilt/${MetaScriptLibrary.ndkHost()}/bin/llvm-nm\").asFile",
		"\t\tFile library = new File(libraryDirectory.get().asFile, 'arm64-v8a/lib" + nativeLibrary + ".so')",
		"\t\tdef symbols = new ByteArrayOutputStream()",
		"\t\texecOperations.exec {",
		"\t\t\tcommandLine(nm.path, '-D', '--defined-only', '--format=just-symbols', library.path)",
		"\t\t\tstandardOutput = symbols",
		"\t\t}",
		"\t\tMap<String, String> kept = [:]",
		"\t\tmapping.get().asFile.eachLine { line ->",
		"\t\t\tdef entry = line =~ /^(\\S+) -> (\\S+):$/",
		"\t\t\tif (entry) kept[entry[0][1]] = entry[0][2]",
		"\t\t}",
		"\t\tList<String> problems = []",
		"\t\tsymbols.toString().readLines().findAll { it.startsWith('Java_') }.each { symbol ->",
		"\t\t\tString owner = jniClass(symbol)",
		"\t\t\tString implemented = \"${library.name} implements its native method ${symbol}\"",
		"\t\t\tif (!kept.containsKey(owner)) problems << \"R8 removed ${owner}, but ${implemented}\".toString()",
		"\t\t\telse if (kept[owner] != owner) problems << \"R8 renamed ${owner} to ${kept[owner]}, but ${implemented}\".toString()",
		"\t\t}",
		"\t\tif (!problems.isEmpty()) {",
		"\t\t\tpackagedOutputs.files.each { it.deleteDir() }",
		"\t\t\tthrow new GradleException(\"MetaScript: \" + problems.unique().join('\\n') +",
		"\t\t\t\t'\\nKeep each class, by name, in the consumer keep rules of the Android library that declares it.')",
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
		"dependencies {",
		"\tgradle.androidLibraries.each { implementation project(it) }",
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
		"\t\tif (variant.buildType == 'release') {",
		"\t\t\tdef nativeClasses = tasks.register(\"verifyNativeClasses${variant.name.capitalize()}\", NativeClassCheck) {",
		"\t\t\t\tmapping = variant.artifacts.get(SingleArtifact.OBFUSCATION_MAPPING_FILE.INSTANCE)",
		"\t\t\t\tlibraryDirectory = library.flatMap { it.outputDirectory }",
		"\t\t\t\tndkDirectory = androidComponents.sdkComponents.ndkDirectory",
		"\t\t\t\tpackagedOutputs.from(layout.buildDirectory.dir(\"outputs/apk/${variant.name}\"), layout.buildDirectory.dir(\"outputs/bundle/${variant.name}\"))",
		"\t\t\t}",
		"\t\t\tdef packaging = [\"assemble${variant.name.capitalize()}\".toString(), \"bundle${variant.name.capitalize()}\".toString()]",
		"\t\t\ttasks.matching { it.name in packaging }.configureEach { dependsOn nativeClasses }",
		"\t\t}",
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
		{ path: "settings.gradle", content: settingsGradle(graph.name, compiler, root + "/" + target.entry) },
		{ path: "build.gradle", content: rootGradle(target) },
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
