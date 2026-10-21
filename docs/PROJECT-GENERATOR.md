# Ion Project Generator

Ion owns project description, graph resolution, native-project emission and
packaging orchestration. Ion runtime owns windows, lifecycle and render-surface
hosting. Neon remains a UI/rendering consumer and is not required to generate
or build an Ion application.

The generator emits macOS and iOS Xcode applications, Android Gradle
applications and Windows Visual Studio applications, using the existing typed-manifest → resolved-graph →
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
- a named struct holding closures for plugins.

### Files: `files`, `Artifact`, `Slot`, `webview()`

A target places files into its product through `files`. An `Artifact` is a named
set of files with one `Slice` per (platform, `Arch`); a `Placement` puts an
artifact into a `Slot` of the product, optionally under a subdirectory. Resolve
picks the slice for the target's platform and arch, so one manifest line serves
every target:

```ms
import { Project, Target, Artifact, Platform, Arch, Slot } from "../../tooling/generator/description";
import { bundlePrefix, webview } from "../../tooling/generator/plugins";

function vendored(file: string): Artifact {
	return {
		name: file,
		license: "MIT",
		slices: [
			{ platform: Platform.Windows, arch: Arch.X64, files: ["vendor/x64/" + file] },
			{ platform: Platform.Windows, arch: Arch.Arm64, files: ["vendor/arm64/" + file] },
		],
	};
}

export const project: Project = {
	name: "Haro",
	targets: [{
		...Target.windowsApp("Haro", "main.ms"),
		files: [
			{ artifact: vendored("conpty.dll"), slot: Slot.Libraries, directory: "" },
			{ artifact: vendored("openConsole.exe"), slot: Slot.Executables, directory: "" },
		],
	}],
	plugins: [bundlePrefix("dev.haro"), webview()],
};
```

- Slots are `Executables`, `Libraries` and `Resources`; each emitter maps a slot to a
  directory of its platform. `directory` is a relative path inside the slot (`""` is the
  slot root), and a file keeps only its basename: `directory + "/" + basename`.
- A slice file is a path relative to the manifest's directory, or absolute; a plugin
  uses an absolute path for files inside Ion. A missing file stops `generate`.
- `assets` is the same mechanism: each entry is a `Resources` placement that keeps its
  relative path, for every platform but Android. An entry that names a directory is
  an Xcode folder reference, as Tuist's `.folderReference(path:)` is: the build copies
  the tree as it is at build time, so files added later need no new `generate`.
- `Target.arch` defaults to `X64` for `windowsApp` and `Arm64` for the others.
- `webview()` places `WebView2Loader.dll` (`vendor/webview2`, x64 only) into Libraries
  of every Windows target. A Windows arm64 target that uses it fails at resolve with the
  missing-slice error, because Ion vendors only x64.
- Resolve stops at the first of: no slice for the target's (platform, arch); a
  placement for an Android target (not supported yet); two different sources written to
  one (target, slot, destination), whoever the owners; a plugin placing into a missing
  target; an invalid `directory`. The same source to the same destination is recorded
  once.

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
are created. `evaluator.ms` is the orchestration entry point behind
`ion generate` (`cli/main.ms`): it creates a temporary evaluator module and
invokes `msc run --target=raiser` for the manifest, resolver, plugins and
emitter.

A plugin is a `Plugin { name, contribute, files }` value. `contribute` receives an
owned snapshot of the target list and returns `BundleId { target, value }`
contributions; `files` receives its own snapshot and returns
`FileContribution { target, placement }` values (a plugin with nothing to place returns
`[]`):

```ms
export function bundlePrefix(prefix: string): Plugin {
	return {
		name: "bundlePrefix(" + prefix + ")",
		contribute: (targets: Span<Target>): Vec<BundleId> => {
			const ids: Vec<BundleId> = [];
			for (const target of targets) ids.push({ target: target.name, value: prefix + "." + target.name });
			return ids;
		},
		files: (targets: Span<Target>): Vec<FileContribution> => [],
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

Validation stops at the first error. `ion generate` prints it on stderr as
`ion generate: <message>` and exits 1 without creating the output directory.

## Build and run

```bash
msc install -g @metascript/ion@file:$PWD   # once, from the Ion checkout
ion generate examples/generator/project.ms /private/tmp/ion-generated
```

Both arguments are optional: the manifest defaults to `project.ms` in the
current directory and the output to `out/xcode` beside the manifest. The
compiler is the `msc` on `PATH` unless `MSC` names another one. The generator
sources are the ones of the checkout `ion` was installed from. The output path
must not exist. A successful generation writes:

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
MSC="$HOME/.metascript/bin/msc" ion generate \
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

The generator owns the program entry, as Tauri's iOS template ships its
`main.mm`: it writes `IonMain.m` beside the project, whose `main` stores the
arguments and environment and runs `MsMain` in an autorelease pool, and the
build phase compiles it with the target's clang flags and links it through
`--link`. An app that defines its own `main` fails to link with a duplicate
symbol; its UIKit start-up (`UIApplicationMain`) runs from `MsMain`, as the
fixture's `host.m` does. `Target.assets` land under the bundle with their
relative path, and `resourcePath()` from `src/window.ms` returns the flat
`.app` directory on iOS, so an app reads `join(resourcePath(), "assets/x.ttf")`;
the working directory of an iOS app is `/`, and Ion does not change it.

A target with `developmentTeam` signs with `CODE_SIGN_STYLE = Automatic` and
that `DEVELOPMENT_TEAM`, as Tuist's `automaticCodeSigning(devTeam:)` does; build
for a device with `-sdk iphoneos -allowProvisioningUpdates`, and override the
team for one build with `DEVELOPMENT_TEAM=<id>` on the `xcodebuild` line.
Without a team the target keeps `CODE_SIGNING_ALLOWED = NO`.

`Target.infoPlist` adds keys Xcode's `INFOPLIST_KEY_*` settings do not cover
(`UIFileSharingEnabled` is one: an `INFOPLIST_KEY_UIFileSharingEnabled` override
is dropped): `infoPlist: [plistBoolean("UIFileSharingEnabled", true)]`, or
`plistString(key, value)`. They go to `<target>-Info.plist` beside the project,
named by `INFOPLIST_FILE`, which Xcode merges with the keys it generates.
Tuist's `.extendingDefault(with:)` takes the same key list but writes its own
defaults into that file too. A key set twice is refused.

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
ion generate examples/generatorAndroid/project.ms out/ionAndroid
cd out/ionAndroid
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

Use the same Bash entry and generated Gradle tasks on Windows, macOS and Linux.
On Windows, `MSC` must name the native `msc.exe`; the generated project pins
that executable. The build-host path has no separate Ion platform launchers.
Windows APK verification is currently compiler-blocked; see the measured
boundary below rather than treating successful generation as an APK claim.

**Windows build-host boundary — 2026-09-30.**

Measured on code/test tree `38aea60fe5fe79d3a1027f0f22b0a837e15fb0d5`,
installed `msc` v0.2.55 binary/support `35601908`, Windows 11 x64, JDK 21
and NDK `28.0.13004108`:

- `python tooling/generator/tests/cli.py out/tmp/unifiedCliGuard`, with `MSC`
  set to the installed native compiler, passed all five invocations.
- `msc check --target=raiser tooling/generator/generate.ms` checked 33 modules;
  resolver 24 assertions, plugin isolation and Android 18 assertions passed.
  `msc check src/index.ms` checked 72 modules with no type errors and an
  existing unused `invoke` import warning.
- The generated project's common NDK selection executed the real Windows
  `clang.cmd` and `llvm-nm.exe` successfully through both Gradle launchers.
  This was an isolated tool-selection smoke, not a native-library or Release
  JNI verification.
- `gradlew.bat --no-daemon --console=plain assembleDebug` reached Java
  compilation and `compileMetaScriptDebug`, then failed: `The system cannot
  find the path specified.` and `error: @compile failed for
  C:/Users/metacraft/.metascript/runtime/core/system.c (exit 1)`.
  A one-line entry without Gradle or spaces in its output path failed through
  the same installed NDK wrapper; that wrapper's `--version` returned zero.

The compiler prerequisite is recorded as an Android sighting in workspace card
`.inbox/compiler/2026-09-20-emcc-spawn-windows.md`. No shim or alternate native
build path was added. No APK, native load, Release JNI, Android lifecycle or
physical-device result was obtained from this Windows run; macOS/Linux builds
were not rerun. The reusable Android runtime host and Neon integration remain
separate from successful project generation.


`Target.androidApp` in `description.ms` owns the defaults in `AndroidSettings`.
`gradle.ms` `gradleProject` validates them and renders every text file;
`generate.ms` adds the wrapper files from `tooling/generator/android/wrapper/`
byte for byte. Why the shape is what it is:

- **One Android target.** The Android part of a graph holds one target with
  no dependency; a second Android target is refused by name. A graph that also
  holds Apple targets writes the Xcode project and the Gradle project side by
  side in one output directory (`generate.ms` `render`), so one `project.ms`
  describes an iOS and an Android build. The minimum API lives
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
  same activity instead of recreating it. The activity is `singleTask` and
  forwards `onNewIntent` as `newIntent(Intent)`, as Tauri's template does, so
  a notification tap or a link reaches the running app, and the app the system
  recreates after killing its process; `getIntent()` stays the launch intent.
  The fixture's `fixture.c` shows the native half; Neon owns the real one.
- **Release signing from the environment.** `ION_ANDROID_STORE_FILE`,
  `ION_ANDROID_STORE_PASSWORD`, `ION_ANDROID_KEY_ALIAS` and
  `ION_ANDROID_KEY_PASSWORD`, or the matching `-Pion.android.*` properties.
  Nothing secret enters the manifest, the graph or the generated files. When
  one is missing, `verifyReleaseSigning` fails and names all of them before any
  native Release work runs. JDK 17 `keytool` writes PKCS12 stores, which
  ignore a separate `-keypass`: the key password is the store password.
- **Package Java is an Android library module.** A package keeps its Java in
  a standard Android library module (its own `build.gradle`, `src/main/java`,
  keep rules through `consumerProguardFiles`) and declares it in its own source
  with the macro from `src/android.ms`:

  ```ms
  import { androidLibrary } from "ion/src/android";

  when (android) {
  	androidLibrary("./android");
  }
  ```

  The path resolves beside the calling module; a directory without
  `build.gradle` fails the compile. Gradle fixes its project list before any
  task runs, so the generated `settings.gradle` runs the pinned
  `msc check <entry> --os=android --cpu=arm64 -d:ionAndroidLibraries=<file>` on
  every invocation. `check` expands the macro each time and never reports up
  to date, and the list starts empty each time, so a removed call drops its
  module on the next build with no clean. A source that does not type-check
  therefore fails configuration, not only the native task. Each declared
  directory becomes a Gradle project built in place, with its build output
  under the root `build/androidLibraries/`; the app depends on every one, and
  the target's compileSdk, minSdk and Java level apply to it. javac errors name
  the package's own file. When a library's javac runs, the variant's APK and
  AAB are removed first, so a failed compile leaves no runnable package.
- **Release refuses a JNI class R8 removed.** An empty consumer keep rule
  otherwise builds green while R8 removes the class, and the app finds no
  listener at run time. `verifyNativeClassesRelease` reads the
  `Java_…` exports of the Release library with the NDK's `llvm-nm` and, when
  R8's mapping dropped or renamed an owning class, deletes the Release APK and
  AAB and fails: `R8 removed dev.ion.fixture.Tap, but libmetascript.so
  implements its native method Java_dev_ion_fixture_Tap_tapped`. A class that
  native code reaches only through `FindClass` or `RegisterNatives`, with no
  exported `Java_…` symbol, is not checked.
- **Not packaged by Ion.** A library that needs `libc++_shared.so` (a C++
  dependency such as Yoga) will not load, because Ion does not inspect the
  library to add runtimes. Making the `.so` self-contained belongs to the
  package that declares the C++ graph, or to msc.

## Windows application

```bash
MSC=C:/Users/you/.metascript/bin/msc.exe ion generate examples/helloWebviewProject.ms C:/work/ion-hello
MSBuild C:/work/ion-hello/IonHello.sln -p:Configuration=Debug -p:Platform=x64
C:/work/ion-hello/bin/IonHello/Debug/IonHello.exe
```

Open `IonHello.sln` in Visual Studio to build, run and debug the same way.
`Target.windowsApp` in `description.ms` owns the defaults. Every placed file,
`assets` included, reaches the product through the slot table below.
`resources/` beside the executable is the directory `ionResourcePath()` serves
`ion://localhost/` from. `visualStudio.ms` renders the
solution and, per target, a `Makefile` vcxproj, `build.cmd`, an `.rc` and an
application manifest. Why the shape is what it is:

- **The resource is a declared input.** `build.cmd` compiles the `.rc` with the
  Windows SDK's `rc.exe`, and msc builds the application's own entry with
  `--link=<res>`, so the app's `build.ms` (`globalImports`, `deps`, `defines`,
  `cc.linkFlags`) applies. Measured on msc `9a4775dc`: a changed `.res` passed
  through `--passL` left the old version in the executable (`Up to date`), while
  the same file under `@link` relinked; `--link` (msc `b267cdb1`) is tracked the
  same way and, unlike `--passL`, keeps `cc.linkFlags`. A generated wrapper entry
  carrying `@link` worked too, but msc finds `build.ms` from the entry, so the
  wrapper hid the app's `build.ms` (Neon's `globalImports` failed with 52 type
  errors).
- **msc owns the executable and its failure.** `build.cmd` runs msc from the
  configuration's intermediate directory, so the source tree receives nothing;
  any failed step deletes the executable, so Visual Studio never launches a stale
  one.
- **Slots map to directories, and a file is never rewritten when identical.**

  | Slot | Directory |
  |---|---|
  | Executables | `%out%` (beside the exe) |
  | Libraries | `%out%` (the DLL search path is the exe directory) |
  | Resources | `%out%resources\` |

  Each placed file becomes `call :place "<source>" "<destination>" || goto fail`. The
  `:place` subroutine skips a destination that `fc /b` finds identical, otherwise makes
  its directory, copies to `<destination>.tmp` and moves that over the destination. An
  identical file keeps its mtime and does not fail while a running app holds the DLL.
  Executables and Libraries share `%out%`, so the emitter compares final paths
  case-insensitively and refuses two sources at one path or any file over `<target>.exe`.
- **`build.cmd` deletes nothing it did not write.** The earlier
  `rmdir /s /q resources` removed what msc writes there, and `generate` refuses an
  existing output directory, so a `bin/` never outlives a change to the manifest and
  nothing goes stale; a file dropped from the manifest is gone after regeneration.
- **The solution is x64 only**, so the emitter refuses a Windows target whose `arch`
  is not `X64`; Ion vendors only the x64 `WebView2Loader.dll`. Toolset
  `v143`, the Build Tools 2022 one. A Windows target has no deployment target and
  refuses one.
- **Project GUIDs derive from the target name**, so the output is byte-identical
  for the same manifest and reordering targets does not renumber them.
- **An entry calls its `main`.** msc stopped calling an unreferenced `main` on
  2026-08-16 (`recompiler/docs/BARE.md`); `examples/helloWebview.ms` linked but
  exited at once until it ended with `exit(main())`.
- **Keep the output path short.** In a directory about 150 characters deep, msc's
  object cache passed `MAX_PATH` and failed with `failed to publish object …
  (target locked by a concurrent reader?)`
  (`~/metascript/.inbox/compiler/2026-09-23-emit-c-long-path-windows.md`); the
  same project built under `C:/Users/<you>/ionGen`.

## Windows and Linux: why this shape

The Windows emitter above follows this; Linux has none yet. Windows keeps the Xcode split: the generator emits a Visual Studio
solution and project that own what Xcode owns on Apple (metadata, the files
beside the executable, signing, packaging, launch and debugging), while msc
keeps the whole executable through one build step, the counterpart of the
"Compile MetaScript" phase and of `compileMetaScript<Variant>`. The project lists
no C source. Metadata on Windows is the icon and version resource and the
application manifest; plugins reach them through the graph, not through
vcxproj text. Linux has no IDE that owns an application shell, so its emitter
writes the shell files directly with the same split: `ion app --target linux`
puts the executable, its resources, the `.desktop` entry and the icon in an
AppDir and packs it with `appimagetool`. The package is an AppImage that uses
the system's GTK4 and WebKitGTK 6.0 (decided 2026-10-18), because Ion's OTA
updates it in place: `apply` renames the new AppImage over `$APPIMAGE`. Flatpak
was weighed and set aside: its `/app` is read-only, so Ion's update channel
would not reach a Flatpak app. `.deb` and `.rpm` are not planned.

Rejected, and why:

- **An `Application` vcxproj that compiles the C msc emits**, as React Native
  Windows does for its C++ (`vnext/templates/cpp-app/windows/MyApp/MyApp.vcxproj`
  at `1f59db1`: `ClCompile`, `ResourceCompile`, toolset `v145`). It moves compile
  and link from msc to MSBuild, which the Apple and Android emitters refuse for
  the same reason.
- **CMake for both platforms**, as Flutter's `windows/runner/` does. It would
  only wrap the same msc call in another format and owns no shell.
- **No IDE project on Windows.** It loses debugging from Visual Studio and the
  Windows Application Packaging Project (`.wapproj`), which is where Visual
  Studio edits the MSIX manifest and signing.
- **RNW's `MakeBundle` pattern as is**
  (`vnext/PropertySheets/Bundle.Common.targets`): it runs the bundler with
  `ContinueOnError="true"`, so a failed bundle still builds green. A failed msc
  build must leave no runnable executable, as on iOS and Android.

What RNW confirms: its `WinMain` (`templates/cpp-app/windows/MyApp/MyApp.cpp`)
reads content from a folder beside the executable, as `ionResourcePath()` reads
`<exe dir>/resources`, and sets per-monitor DPI awareness in code rather than in
a manifest, as `src/platform/windows/core/lifecycle.c` does. Its `run-windows`
requires Visual Studio 18.6 through `vswhere`
(`packages/@react-native-windows/cli/src/utils/msbuildtools.ts`), which refuses
Build Tools 2022 (17.14, toolset `v143`).

The resource is the one place where the split differs from Apple: Info.plist
sits outside the binary, while the Windows icon and manifest are linked into
it. MSBuild compiles the `.rc`, and msc links the `.res` through `--link`
(see "Windows application").
Measured on tree `dcd8becb7b21f83bbf900c7f1a66a824caf35048`, msc v0.3.3
`9a4775dc`, Windows 11: `msc build examples/helloWebview.ms` writes
`out/debug/helloWebview.pdb` beside the executable.

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

`tooling/generator/tests/cli.py` exercises the common generator entry with
relative and native absolute paths, fresh-process determinism, overwrite
preservation, invalid-manifest isolation, nested Android output with spaces,
the default manifest and output, and that no evaluator directory is left in
the temporary directory.
It can run independently of Xcode:

```bash
MSC=/absolute/path/to/msc python tooling/generator/tests/cli.py out/generatorTests
```

`tooling/generator/tests/android.ms` pins the typed defaults, every validation
message, the emitted file set and the contract lines of each file, including
the Windows `.cmd`/`.exe` NDK tool selection.
`tooling/generator/tests/windows.ms` pins the Windows defaults, refusals, the
emitted file set and the contract lines of the solution, project, build script,
resource. `tooling/generator/tests/windows.py` generates the
fixture twice and compares the trees, builds Debug and Release with MSBuild
(found through `vswhere`), checks each product's executable, loader and
`resources/`, launches `IonHello.exe` from another directory until it logs
`auto-probe: ipc alive` and the `addNumbers` round trip, builds a fixture app
(outside the checkout) whose entry calls a function only its `build.ms`
`globalImports` supplies, relinks it after the generated `.rc` changes (the new
`ProductName` is in the executable), breaks the fixture's entry to prove a failed
build leaves no executable and recovers, checks that a stale resource is removed, and that `git status` of the checkout is unchanged.
On a Windows host `run.sh` runs the unit tests, `cli.py` and `windows.py`; on
macOS it runs the Xcode, iOS and Android lanes as before.

Measured 2026-10-14 on code/test tree `5fa73c5519b92a024896ed18dbdce53727fdfd63`,
msc v0.3.3 `9a4775dc`, Visual Studio Build Tools 2022 17.14, Windows 11:
`MSC=C:/Users/metacraft/.metascript/bin/msc.exe bash tooling/generator/tests/run.sh`
exited 0 (resolver 24, Android 70 and Windows 39 assertions, plugin isolation,
`cli.py`, `windows.py`). Not run that day: the macOS lanes, the Visual Studio IDE
(only Build Tools are installed, so F5 debugging is unverified).

`tooling/generator/tests/android.py` generates twice under paths with spaces and
compares whole trees, then checks overwrite and invalid-manifest refusal with no
output, Debug and Release libraries (exports, 16 KiB `PT_LOAD`, stripped
Release, distinct work directories), 16 KiB APK alignment, refused unsigned
Release, a signed APK (`apksigner`) and AAB (`jarsigner`) from a throwaway key,
and no secret in the project. On an Android 36 emulator it launches Debug and
Release, drives rotation, home, relaunch and task removal, and rebuilds after
source, header and deliberate compile-failure edits. The fixture declares its
`android/` library: a tap on the label reaches native through the library's
listener in Debug and Release; an emptied keep rule fails Release with no
package left; a Java edit changes the tapped tag with no clean; a javac failure
names the package file and leaves no `app-debug.apk`; removing the declaration
drops the library and the app reports the listener missing. `ANDROID_SERIAL` selects
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

Measured 2026-09-25 on code/test tree
`14817032611a916b47d643a1ac8d5543c92326ab`, `msc` v0.2.55 build `242b735a`,
the same Gradle, AGP, NDK and JDK, Pixel 9 Pro emulator on Android 36 with
`ANDROID_SERIAL=emulator-5554`: `tests/android.py` passed. A tap on the label
logged `tap tag=7` through the library's listener in Debug and Release. An
emptied `consumer-rules.pro` failed Release with `R8 removed
dev.ion.fixture.Tap, …` and left no APK or AAB. Editing `Tap.java` logged
`tap tag=107` with no clean. A missing semicolon failed at `source with
spaces/android/src/main/java/dev/ion/fixture/Tap.java:14` and left no
`app-debug.apk`. Removing the declaration dropped the library project, and the
app logged `listener=missing`. Unchanged `5b26122` passed on the same emulator
just before. Two earlier runs of this tree stopped at the emulator, not
the build, with the host at load average 40–74: a "System UI isn't responding"
dialog covered the app, and in the other run task removal left the activity
`isExiting` with no `destroy`.

The Recompiler candidate must independently pass its Raiser tests, full compiler
suite, corpus regression comparison and sanitizer corpus. Ion's test script is
a consumer gate, not a substitute for compiler verification.

## Current boundary

- macOS and iOS application targets are supported, but a single graph cannot
  mix their SDKs. A graph may add one Android application target to either.
- Android builds only `arm64-v8a`. The native task accepts macOS and Linux
  hosts and refuses others; only macOS has been run. Play upload is not
  verified.
- iOS Debug uses an ordinary compiler build; Release adds `--release`.
  macOS retains its existing compiler command in both configurations.
- Manifests are trusted programs. Current Raiser host bindings expose filesystem
  and subprocess operations; there is no capability sandbox.
- Evaluation starts a fresh Raiser process for each generation. There is no
  persistent evaluator, hot reload or manifest cache.
- Products are unsigned unless the target names a `developmentTeam`. Simulator
  ad-hoc signing is exercised by enabling Xcode signing; with `ION_IOS_TEAM`
  set, `tests/ios.py` builds and team-signs the fixture for `iphoneos`
  (measured 2026-10-22, team-signed, asset in the bundle). Installing and running
  on a device, archive/export, universal binaries and App Store distribution
  are not verified or promised.
- No Neon counter, iOS Ion window/webview API or reusable UIKit host is supplied
  by this generator milestone. Simulator x86_64 is accepted by the script but
  has not been exercised; the development gate uses arm64.
- The generated project embeds absolute source and compiler paths. Regenerate
  after moving the checkout or selecting a different compiler path.
- PBX object identifiers are derived from target and dependency positions.
  Output is byte-identical for the same manifest, but reordering targets
  renumbers objects.
- Plugins contribute bundle identifiers and file placements. Settings and new
  targets are not contribution kinds yet. Android placements are not supported
  (resolve refuses them). Build steps and foreign builds come in stage 2. On
  macOS and iOS each slot becomes a `PBXCopyFilesBuildPhase` (Executables spec 6,
  Libraries spec 10, Resources spec 7), emitted text only: `tests/resolve.ms`
  checks it, and no Xcode build has run it.
- A Windows graph holds only Windows targets, x64 only. No icon resource is
  emitted yet (the manifest has no icon field), the version is fixed at
  `1.0.0.0` as on iOS, and nothing is signed or packaged; the installer is
  `ion app --target windows` (`cli/main.ms` `winApp`). `build.cmd` needs
  `rc.exe` on `PATH`, which MSBuild and a developer prompt provide.
- An `androidLibrary` path containing `..` fails at compile time: Raiser's
  `Array.pop` breaks `join` (`~/metascript/.inbox/compiler/2026-09-25-raiser-array-pop-fails.md`).

The next product step is to stabilize the project-description package and fold
the generator command into Ion's primary CLI without moving graph or emitter
responsibilities into Neon or Recompiler.
