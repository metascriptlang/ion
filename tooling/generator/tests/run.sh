#!/usr/bin/env bash
set -euo pipefail

compiler=${MSC:?Set MSC to the source-built Recompiler candidate}
repo=$(cd "$(dirname "$0")/../../.." && pwd)
results=$(mktemp -d "${TMPDIR:-/tmp}/ion-generator-tests.XXXXXX")
cd "$repo"

"$compiler" run tooling/generator/tests/resolve.ms --target=raiser > "$results/resolve.log" 2>&1
"$compiler" run tooling/generator/tests/pluginIsolation.ms --target=raiser > "$results/isolation.log" 2>&1
"$compiler" run tooling/generator/tests/android.ms --target=raiser > "$results/android-unit.log" 2>&1

python3 tooling/generator/tests/cli.py "$results"
plutil -lint "$results/first/IonGenerator.xcodeproj/project.pbxproj"


xcodebuild -project "$results/first/IonGenerator.xcodeproj" -target IonGenerator -configuration Debug -jobs 1 \
	SYMROOT="$results/products" OBJROOT="$results/objects" build > "$results/xcodebuild.log" 2>&1
for app in IonGenerator IonPreview; do
	bundle="$results/products/Debug/$app.app"
	test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$bundle/Contents/Info.plist")" = "dev.ion.$app"
	test "$(ION_GENERATOR_SMOKE=1 "$bundle/Contents/MacOS/$app")" = "Ion Generator window created"
done
python3 tooling/generator/tests/ios.py "$results"
python3 tooling/generator/tests/android.py "$results"
printf 'PASS: resolver, plugin isolation, generator behavior, Xcode syntax, xcodebuild with dependency, app smoke, iOS and Android fixtures\nlogs=%s\n' "$results"
