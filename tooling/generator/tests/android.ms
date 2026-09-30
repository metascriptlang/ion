import { Project, Target } from "../description";
import { bundlePrefix } from "../plugins";
import { resolve } from "../resolve";
import { gradleProject, GeneratedFile } from "../gradle";
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
	check(!rendered.ok, "expected refusal: " + message);
}

function expectError(targets: Vec<Target>, message: string): void {
	expectRendered(render(targets), message);
}

const app = Target.androidApp("Mobile", "main.ms");
const first = render([app]);
check(first.ok, "Android graph emits a Gradle project");
const second = render([app]);
if (first.ok && second.ok) {
	check(JSON.stringify(first.value) == JSON.stringify(second.value), "deterministic output");
}

const android = resolve({ name: "Mobile", targets: [app], plugins: [bundlePrefix("dev.ion")] });
if (android.ok) {
	const xcode = xcodeProject(android.value, "/source", "/compiler");
	check(!xcode.ok, "Xcode refuses Android targets");
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
