#!/usr/bin/env bash
set -euo pipefail

compiler=${MSC:?Set MSC to the source-built Recompiler candidate}
repo=$(cd "$(dirname "$0")/../../.." && pwd)
results=$(mktemp -d "${TMPDIR:-/tmp}/ion-generator-tests.XXXXXX")
cd "$repo"

case "$(uname -s)" in
	Darwin) host=macos python=python3 ;;
	MINGW* | MSYS*) host=windows python=python results=$(cygpath -m "$results") ;;
	*) printf 'FAIL: no generator lane for host %s\n' "$(uname -s)" >&2; exit 1 ;;
esac

"$compiler" run --target=raiser tooling/generator/tests/resolve.ms > "$results/resolve.log" 2>&1
"$compiler" run --target=raiser tooling/generator/tests/pluginIsolation.ms > "$results/isolation.log" 2>&1
"$compiler" run --target=raiser tooling/generator/tests/android.ms > "$results/android-unit.log" 2>&1
"$compiler" run --target=raiser tooling/generator/tests/windows.ms > "$results/windows-unit.log" 2>&1

"$python" tooling/generator/tests/cli.py "$results"

if [ "$host" = windows ]; then
	"$python" tooling/generator/tests/windows.py "$results"
	printf 'PASS (Windows host): resolver, plugin isolation, Android and Windows emitters, generator behavior, Windows fixture\nlogs=%s\n' "$results"
	exit 0
fi

plutil -lint "$results/first/IonGenerator.xcodeproj/project.pbxproj"
xcodebuild -project "$results/first/IonGenerator.xcodeproj" -target IonGenerator -configuration Debug -jobs 1 \
	SYMROOT="$results/products" OBJROOT="$results/objects" build > "$results/xcodebuild.log" 2>&1
for app in IonGenerator IonPreview; do
	bundle="$results/products/Debug/$app.app"
	test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$bundle/Contents/Info.plist")" = "dev.ion.$app"
	test "$(ION_GENERATOR_SMOKE=1 "$bundle/Contents/MacOS/$app")" = "Ion Generator window created"
done
"$python" tooling/generator/tests/ios.py "$results"
"$python" tooling/generator/tests/android.py "$results"
printf 'PASS (macOS host): resolver, plugin isolation, Android and Windows emitters, generator behavior, Xcode syntax, xcodebuild with dependency, app smoke, iOS and Android fixtures\nlogs=%s\n' "$results"
