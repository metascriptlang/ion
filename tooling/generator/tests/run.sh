#!/usr/bin/env bash
set -euo pipefail

compiler=${MSC:?Set MSC to the source-built Recompiler candidate}
repo=$(cd "$(dirname "$0")/../../.." && pwd)
results=$(mktemp -d /private/tmp/ion-generator-tests.XXXXXX)
cd "$repo"

"$compiler" run tooling/generator/tests/resolve.ms --target=raiser > "$results/resolve.log" 2>&1
test "$(<"$results/resolve.log")" = "resolve: 19 assertions passed"
"$compiler" run tooling/generator/tests/pluginIsolation.ms --target=raiser > "$results/isolation.log" 2>&1
test "$(<"$results/isolation.log")" = "plugin isolation: passed"

evaluators_before=$(find /private/tmp -maxdepth 1 -name 'ion-generator.*' | wc -l)
generate=tooling/generator/ion-generate
"$generate" examples/generator/project.ms "$results/first" > "$results/first.log" 2>&1
"$generate" examples/generator/project.ms "$results/second" > "$results/second.log" 2>&1
test "$(find /private/tmp -maxdepth 1 -name 'ion-generator.*' | wc -l)" = "$evaluators_before"
cmp "$results/first/graph.json" "$results/second/graph.json"
cmp "$results/first/IonGenerator.xcodeproj/project.pbxproj" "$results/second/IonGenerator.xcodeproj/project.pbxproj"
plutil -lint "$results/first/IonGenerator.xcodeproj/project.pbxproj"

if "$generate" tooling/generator/tests/invalid.ms "$results/invalid" > "$results/invalid.out" 2> "$results/invalid.err"; then
	printf 'FAIL: invalid manifest returned success\n' >&2
	exit 1
fi
test ! -e "$results/invalid"
test ! -s "$results/invalid.out"
rg -q "^ion generate: the target 'Duplicate' is declared multiple times$" "$results/invalid.err"
if "$generate" examples/generator/project.ms "$results/first" > "$results/existing.log" 2>&1; then
	printf 'FAIL: existing output was overwritten\n' >&2
	exit 1
fi
cmp "$results/first/graph.json" "$results/second/graph.json"
cmp "$results/first/IonGenerator.xcodeproj/project.pbxproj" "$results/second/IonGenerator.xcodeproj/project.pbxproj"

rm -rf examples/generator/out/xcode
(cd examples/generator && "$repo/tooling/generator/ion-generate" > "$results/default.log" 2>&1)
test -f examples/generator/out/xcode/graph.json
cmp examples/generator/out/xcode/graph.json "$results/first/graph.json"
rm -rf examples/generator/out/xcode

xcodebuild -project "$results/first/IonGenerator.xcodeproj" -target IonGenerator -configuration Debug -jobs 1 \
	SYMROOT="$results/products" OBJROOT="$results/objects" build > "$results/xcodebuild.log" 2>&1
for app in IonGenerator IonPreview; do
	bundle="$results/products/Debug/$app.app"
	test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$bundle/Contents/Info.plist")" = "dev.ion.$app"
	test "$(ION_GENERATOR_SMOKE=1 "$bundle/Contents/MacOS/$app")" = "Ion Generator window created"
done
printf 'PASS: resolver, plugin isolation, fresh-process determinism, Xcode syntax, invalid manifest, overwrite refusal, default manifest and output, xcodebuild with dependency, app smoke\nlogs=%s\n' "$results"
