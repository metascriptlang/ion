# Ion Project Generator

Ion owns project description, graph resolution, native-project emission and
packaging orchestration. Ion runtime owns windows, lifecycle and render-surface
hosting. Neon remains a UI/rendering consumer and is not required to generate
or build an Ion application.

The generator emits macOS and iOS Xcode applications and Android Gradle
applications, using the existing typed-manifest → resolved-graph →
platform-emitter boundary. The emitted project is a deterministic output:
configure the manifest and regenerate rather than editing it. Manifest evaluation
uses the Raiser backend; there is no native fallback.

## Manifest surface

A manifest is an ordinary checked MetaScript module with one named export:

```ms
import { Project, Target } from "../../tooling/generator/description";
import { bundlePrefix } from "../../tooling/generator/plugins";

const app = Target.app("IonGenerator", "main.ms");

export const project: Project = {
	name: "IonGenerator",
	targets: [{ ...app, dependencies: ["IonPreview"] }, { ...app, name: "IonPreview" }],
	plugins: [bundlePrefix("dev.ion")],
};
```

The API deliberately uses normal language features:

- `struct` and `Vec<T>` for owned descriptions;
- static extensions for `Target.app`, `Target.iosApp` and `Target.androidApp`;
- spread for local variants;
- `Result<T, string>` for validation and emission errors;
- a named struct holding a closure for plugins.

Macros, decorators and a generator-specific keyword are not part of the
surface. Runnable manifests are `examples/generator/project.ms` (macOS),
`examples/generatorIos/project.ms` (iOS) and
`examples/generatorAndroid/project.ms` (Android).

## Pipeline

```text
project.ms
  → checked multi-module MetaScript
  → Raiser evaluation
  → Project
  → validation + plugin contributions
  → Graph
  → deterministic PBX project + graph.json
  → xcodebuild
  → Ion .app
```

`tooling/generator/description.ms` owns the public value model.
`resolve.ms` validates names, duplicate targets, missing dependencies, cycles
and bundle identities. `xcode.ms` is the platform emitter. `generate.ms`
validates filesystem inputs, renders everything before writing and refuses to
touch an existing output directory; missing parent directories of the output
are created. `cli.ms` is the orchestration entry point: it creates a temporary
evaluator module and invokes `msc run --target=raiser` for the manifest,
resolver, plugins and emitter. `ion-generate` is a shell wrapper that runs
`cli.ms` itself through Raiser, so the generator ships no compiled binary.

A plugin is a `Plugin { name, contribute }` value. `contribute` receives an
owned snapshot of the target list and returns `BundleId { target, value }`
contributions:

```ms
export function bundlePrefix(prefix: string): Plugin {
	return {
		name: "bundlePrefix(" + prefix + ")",
		contribute: (targets: Span<Target>): Vec<BundleId> => {
			const ids: Vec<BundleId> = [];
			for (const target of targets) ids.push({ target: target.name, value: prefix + "." + target.name });
			return ids;
		},
	};
}
```

The resolver applies contributions centrally and stamps each recorded
`BundleIdentity` with its owner: `manifest` for a `bundleId` written in the
manifest, `plugin <name>` for a contribution. Plugins run in manifest order
after structural validation. A plugin cannot mutate the resolved graph or name
its own provenance. Conflicts name both sides:

```text
bundle identity conflict for 'Studio': manifest sets 'dev.app.Studio', plugin bundlePrefix(dev.ion) sets 'dev.ion.Studio'
circular dependency between targets: Studio -> Tool -> Studio
couldn't find target 'Missing' required by 'Studio'
the target 'Studio' is declared multiple times
```

Validation stops at the first error. `ion-generate` prints it on stderr as
`ion generate: <message>` and exits 1 without creating the output directory.

## Build and run

```bash
tooling/generator/ion-generate examples/generator/project.ms /private/tmp/ion-generated
```

Both arguments are optional: the manifest defaults to `project.ms` in the
current directory and the output to `out/xcode` beside the manifest. The
compiler is the `msc` on `PATH` unless `MSC` names another one. The wrapper
passes its inputs to `cli.ms` as `ION_GENERATE_MANIFEST`, `ION_GENERATE_OUTPUT`
and `ION_GENERATE_ROOT`. The output path must not exist. A successful generation writes:

```text
/private/tmp/ion-generated/
  graph.json
  IonGenerator.xcodeproj/project.pbxproj
```

The generated build phase records the absolute compiler and source-root paths,
then compiles each target entry with MetaScript. Build and smoke the example:

```bash
xcodebuild \
  -project /private/tmp/ion-generated/IonGenerator.xcodeproj \
  -target IonGenerator \
  -configuration Debug \
  -jobs 1 \
  SYMROOT=/private/tmp/ion-products \
  OBJROOT=/private/tmp/ion-objects \
  build

ION_GENERATOR_SMOKE=1 \
  /private/tmp/ion-products/Debug/IonGenerator.app/Contents/MacOS/IonGenerator
```

`IonGenerator` depends on `IonPreview`, so building the `IonGenerator` target also
builds `IonPreview.app`. The smoke process prints `Ion Generator window
created`, closes the window and returns zero.

## iOS development application

The iOS example is an Ion-owned UIKit fixture, not an implementation of Ion's
desktop runtime on iOS and not a Neon integration. Its native lifecycle bridge
is local to the example; the subsequent iOS host work owns the reusable host.

```bash
MSC="$HOME/.metascript/bin/msc" tooling/generator/ion-generate \
  examples/generatorIos/project.ms /private/tmp/ion-ios-generated

xcodebuild -project /private/tmp/ion-ios-generated/IonIos.xcodeproj \
  -target IonIos -configuration Debug -sdk iphonesimulator -jobs 1 \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  SYMROOT="/private/tmp/ion ios products" OBJROOT="/private/tmp/ion ios objects" \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build

xcrun simctl install booted "/private/tmp/ion ios products/Debug-iphonesimulator/IonIos.app"
xcrun simctl launch booted dev.ion.IonIos
```

Use an already booted iOS simulator for the last two commands. For an unsigned
device build, select `-sdk iphoneos` and omit the signing overrides.

The compiler owns the entire executable: generated C, runtime, package native
directives, compile, link and incremental cache. Xcode owns the application
bundle, generated Info.plist, signing and launch. The PBX project deliberately
has no inventory of compiler/runtime/Yoga sources. Ion imports neither Neon nor
Yoga to generate a project.

`Target.iosApp` in `tooling/generator/description.ms` owns the defaults; a
manifest can override its deployment target using ordinary struct spread.
`iosScript` in `tooling/generator/xcode.ms` is the build-environment contract.
The always-run phase pins the compiler and source entry at generation, builds
in Xcode's target/configuration/SDK/architecture-specific temporary directory,
and declares the stable bundle executable output. It does not synthesize a
`build.ms`, use source-tree `out/`, or force/clean the compiler cache.

Native archives must be dependencies declared with `@link`, not merely paths
passed as raw linker flags with `@passL`. On installed compiler `d757c7e1`,
replacing the same archive under `@passL` left the old executable value;
declaring it with `@link` rebuilt correctly. This is why the incremental
fixture uses the same `@link` contract as Recompiler's native-boundary guard.

## Android application

```bash
tooling/generator/ion-generate examples/generatorAndroid/project.ms /private/tmp/ion-android
cd /private/tmp/ion-android
./gradlew assembleDebug
adb install app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n dev.ion.IonAndroid/dev.metascript.app.MainActivity

ION_ANDROID_STORE_FILE=/abs/release.jks ION_ANDROID_STORE_PASSWORD=… \
ION_ANDROID_KEY_ALIAS=… ION_ANDROID_KEY_PASSWORD=… \
  ./gradlew assembleRelease bundleRelease
```

Pass the output path: the default is still `out/xcode`. The build machine needs
JDK 17+, `ANDROID_HOME` with the configured platform and NDK, and network access
the first time the wrapper downloads Gradle. It does not need a global Gradle.

`Target.androidApp` in `description.ms` owns the defaults in `AndroidSettings`.
`gradle.ms` `gradleProject` validates them and renders every text file;
`generate.ms` adds the wrapper files from `tooling/generator/android/wrapper/`
byte for byte. Why the shape is what it is:

- **One target, Android only.** An Android graph with a second target, a
  dependency, or a macOS/iOS target is refused by name. The minimum API lives
  only in `android.minSdk`; an Android target that sets `deploymentTarget` is
  refused rather than reconciled.
- **Pinned toolchain.** Gradle 9.3.1 with its distribution SHA-256 and AGP
  9.1.0: the pair the Android boundary probe proved on this machine. The wrapper
  jar is Gradle's own (SHA-256 `b3a875dd…ec13`, the published checksum), vendored
  so that generation needs no Gradle and output does not depend on the one that
  is installed. NDK 28 is the floor because NDK 27.1 linked the same library
  with 4096-byte `PT_LOAD` segments, which puts Android 16 KiB devices in
  compatibility mode.
- **msc owns the native library.** Each variant registers
  `compileMetaScript<Variant>`, which runs the pinned compiler with
  `--os=android --cpu=arm64 --app=lib` and the NDK's
  `aarch64-linux-android<minSdk>-clang` wrapper, found through AGP's
  `ndkDirectory`. It works in `app/build/metascript/<variant>` and writes
  `lib` + `nativeLibrary` + `.so` into a generated `jniLibs` directory. The
  task is never up to date: msc's cache decides what to rebuild. Release adds
  `--release --strip`. When msc fails, the task deletes its own output and that
  variant's APK and AAB output directories, so no runnable stale package
  survives. Gradle holds no C source, header list, CMake or prebuilt archive.
- **Package-stable bootstrap.** The Java package and the Gradle namespace are
  always `dev.metascript.app`; `applicationId` is the resolved bundle identity.
  So the JNI symbols (`Java_dev_metascript_app_NativeApp_start` and so on) do
  not change with the application id, and the native side can be written once.
  `MainActivity` creates the root `FrameLayout` and forwards start, measured
  resize, pause, resume and destroy on the main thread. The manifest declares
  `configChanges` for size and orientation, so rotation reaches `resize` in the
  same activity instead of recreating it. The fixture's `fixture.c` shows the
  native half; Neon owns the real one.
- **Release signing from the environment.** `ION_ANDROID_STORE_FILE`,
  `ION_ANDROID_STORE_PASSWORD`, `ION_ANDROID_KEY_ALIAS` and
  `ION_ANDROID_KEY_PASSWORD`, or the matching `-Pion.android.*` properties.
  Nothing secret enters the manifest, the graph or the generated files. When
  one is missing, `verifyReleaseSigning` fails and names all of them before any
  native Release work runs. JDK 17 `keytool` writes PKCS12 stores, which
  ignore a separate `-keypass`: the key password is the store password.
- **Not packaged by Ion.** A library that needs `libc++_shared.so` (a C++
  dependency such as Yoga) will not load, because Ion does not inspect the
  library to add runtimes. Making the `.so` self-contained belongs to the
  package that declares the C++ graph, or to msc.

## Verification

```bash
MSC=/absolute/path/to/msc bash tooling/generator/tests/run.sh
```

The gate runs resolver and plugin-isolation checks, fresh-process graph/PBX
determinism, `plutil`, invalid-manifest and overwrite refusal, and the macOS
dependency-app build and launch. `tooling/generator/tests/ios.py` adds actual
simulator Debug/Release launch, ad-hoc signature verification, unsigned device
build, Mach-O/Info.plist minimum agreement, the iPhone and iPad orientation
lists (portrait, upside-down portrait, both landscapes) with no Xcode
orientation warning on the device build, spaced source/product/build paths,
native source/header/archive edits, compiler failure recovery, and rejected
Xcode environments. It creates and deletes its own simulator and retains logs
and a screenshot under the printed results directory. Xcode, Python 3 and an
installed iOS simulator runtime/device type are required.

`tooling/generator/tests/android.ms` pins the typed defaults, every validation
message, the emitted file set and the contract lines of each file.
`tooling/generator/tests/android.py` generates twice under paths with spaces and
compares whole trees, then checks overwrite and invalid-manifest refusal with no
output, Debug and Release libraries (exports, 16 KiB `PT_LOAD`, stripped
Release, distinct work directories), 16 KiB APK alignment, refused unsigned
Release, a signed APK (`apksigner`) and AAB (`jarsigner`) from a throwaway key,
and no secret in the project. On an Android 36 emulator it launches Debug and
Release, drives rotation, home, relaunch and task removal, and rebuilds after
source, header and deliberate compile-failure edits. `ANDROID_SERIAL` selects
a device; without it the script boots the AVD named by `ION_ANDROID_AVD`
(default `Pixel_9_Pro`) when no emulator is attached, and then waits for the
launcher to hold focus: right after `sys.boot_completed` a cold emulator showed
"System UI isn't responding" over the app, and once recreated the activity
before its first layout. Rotation goes through `cmd window user-rotation`;
writing `user_rotation` with `settings put` did not rotate a cold emulator. The
script restores the device's rotation mode. A physical device kills the
process when its task is removed, so the same-process check runs before the
task removal.

Measured 2026-09-22 on code/test tree
`d8eea541f1eacc34c117501c2723c1d35f803dbf`, installed `msc` v0.2.55
binary/support `d757c7e1`, Xcode 26.6 (17F113), arm64 host and iOS 26.5 simulator:
the command above exited 0. Both simulator configurations launched the UIKit
fixture; the device executable and generated plist both declare iOS 15.0.
The iOS incremental sequence produced native values 17 → 27 → 33 → 40 → 62
after source, header and declared-archive changes without project regeneration.
The repository gate also passed all nine commands: library check, seven test
entry files, and the macOS example build.

The gate initially found two stale `navpolicy.ms` expectations that allowed
`file://`. The unchanged arc-base sources at `33b9e98` reproduced both failures;
the tests now expect the block already required by `navpolicy.h` and implemented
by `navpolicy.c`. No navigation runtime behavior changed.

Measured 2026-09-23 on code/test tree `b6dc014`, same toolchain: the command
above exited 0 with the orientation pin. Without the emitter change the pin
fails on the missing `UISupportedInterfaceOrientations~iphone` key and the
device build warns "All interface orientations must be supported unless the app
requires full screen."

Measured 2026-09-23 on code/test tree
`28d92d2cf8746f268e623982d5935d9d0ea6248a`, `msc` v0.2.55 build `e5f0ec68`,
Gradle 9.3.1, AGP 9.1.0, NDK 28.0.13004108, Zulu JDK 17.0.18, Pixel 9 Pro
emulator on Android 36: `tests/android.py` passed. Debug library 958984 bytes,
stripped Release 331864; Debug APK 1288694, signed Release APK 370658
(v1 + v2 verified), AAB 161945. In one process: start, resume,
`resize 1280x2856`, `2856x1280`, `1280x2856`, pause, resume, destroy. Native
values went 17 (Debug and Release) → 27 after the source edit → 33 after the
header edit; the forced failure left neither the library nor `app-debug.apk`,
and the fixed source rebuilt to 33.

Measured the same day on tree `70d7fa7c532f6f02a2047a9d9eaddf06f3dbeda0` and again on `59ca40236110b79ef2c1f9d2b9d186b415ccea74`, same toolchain, on a physical Solana
Seeker (Android 16, API 36, arm64-v8a, 4 KiB pages) over USB with
`ANDROID_SERIAL` set: `tests/android.py` passed. Debug and Release both launched
with native value 17; one process logged start, resume, `resize 1200x2670`,
`2670x1200`, `1200x2670`, pause, resume, destroy; the incremental sequence went
17 → 27 → 33, failed and recovered at 33, as on the emulator. The phone's
auto-rotate setting read the same before and after.

The Recompiler candidate must independently pass its Raiser tests, full compiler
suite, corpus regression comparison and sanitizer corpus. Ion's test script is
a consumer gate, not a substitute for compiler verification.

## Current boundary

- macOS and iOS application targets are supported, but a single graph cannot
  mix their SDKs. Generate separate projects for mixed-platform applications.
  An Android graph holds one Android application target.
- Android builds only `arm64-v8a`. The native task accepts macOS and Linux
  hosts and refuses others; only macOS has been run. Play upload is not
  verified.
- iOS Debug uses an ordinary compiler build; Release adds `--release`.
  macOS retains its existing compiler command in both configurations.
- Manifests are trusted programs. Current Raiser host bindings expose filesystem
  and subprocess operations; there is no capability sandbox.
- Evaluation starts a fresh Raiser process for each generation. There is no
  persistent evaluator, hot reload or manifest cache.
- `ion-generate` remains a separate shell entry point, not `ion generate`.
  Migrating it to the compiler's package-command surface is separate work.
- Products are unsigned by default. Simulator ad-hoc signing is exercised by
  enabling Xcode signing; physical-device signing/run, archive/export,
  universal binaries and App Store distribution are not verified or promised.
- No Neon counter, iOS Ion window/webview API or reusable UIKit host is supplied
  by this generator milestone. Simulator x86_64 is accepted by the script but
  has not been exercised; the development gate uses arm64.
- The generated project embeds absolute source and compiler paths. Regenerate
  after moving the checkout or selecting a different compiler path.
- PBX object identifiers are derived from target and dependency positions.
  Output is byte-identical for the same manifest, but reordering targets
  renumbers objects.
- Plugins contribute bundle identifiers only. Settings, files and new targets
  are not contribution kinds yet.

The next product step is to stabilize the project-description package and fold
the generator command into Ion's primary CLI without moving graph or emitter
responsibilities into Neon or Recompiler.
