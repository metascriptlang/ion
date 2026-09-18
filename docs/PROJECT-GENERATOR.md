# Ion Project Generator

Ion owns project description, graph resolution, native-project emission and
packaging orchestration. Ion runtime owns windows, lifecycle and render-surface
hosting. Neon remains a UI/rendering consumer and is not required to generate
or build an Ion application.

The current generator is a macOS proof of concept inspired by Tuist's boundary
between a typed manifest, a resolved graph and a platform emitter. Manifest
evaluation uses the Raiser backend; there is no native fallback.

## Manifest surface

A manifest is an ordinary checked MetaScript module with one named export:

```ms
import { Project, Target } from "../../tooling/generator/description";
import { bundlePrefix } from "../../tooling/generator/plugins";

const studio = Target.app("IonStudio", "main.ms");

export const project: Project = {
	name: "IonStudio",
	targets: [{ ...studio, dependencies: ["IonPreview"] }, { ...studio, name: "IonPreview" }],
	plugins: [bundlePrefix("dev.ion")],
};
```

The API deliberately uses normal language features:

- `struct` and `Vec<T>` for owned descriptions;
- a static extension for `Target.app`;
- spread for local variants;
- `Result<T, string>` for validation and emission errors;
- a named struct holding a closure for plugins.

Macros, decorators and a generator-specific keyword are not part of the
surface. The complete runnable example is `examples/generator/Project.ms`.

## Pipeline

```text
Project.ms
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
touch an existing output directory. `cli.ms` is native orchestration that
creates a temporary evaluator module and explicitly invokes
`msc run --target=raiser` for the manifest, resolver, plugins and emitter.

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

Use a source-built Recompiler containing the required Raiser contracts:

```bash
export MSC=/absolute/path/to/msc
$MSC build tooling/generator/cli.ms --cc=clang --output=bin/ion-generate
./bin/ion-generate examples/generator/Project.ms /private/tmp/ion-generated
```

The output path must not exist. A successful generation writes:

```text
/private/tmp/ion-generated/
  graph.json
  IonStudio.xcodeproj/project.pbxproj
```

The generated build phase records the absolute compiler and source-root paths,
then compiles each target entry with MetaScript. Build and smoke the example:

```bash
xcodebuild \
  -project /private/tmp/ion-generated/IonStudio.xcodeproj \
  -target IonStudio \
  -configuration Debug \
  -jobs 1 \
  SYMROOT=/private/tmp/ion-products \
  OBJROOT=/private/tmp/ion-objects \
  build

ION_GENERATOR_SMOKE=1 \
  /private/tmp/ion-products/Debug/IonStudio.app/Contents/MacOS/IonStudio
```

`IonStudio` depends on `IonPreview`, so building the `IonStudio` target also
builds `IonPreview.app`. The smoke process prints `Ion Generator window
created`, closes the window and returns zero.

## Verification

```bash
MSC=/absolute/path/to/msc bash tooling/generator/tests/run.sh
```

The gate builds the native orchestration CLI, runs resolver and plugin-isolation
tests through Raiser, evaluates the manifest in two fresh processes, compares
the graph and PBX outputs byte-for-byte, checks no evaluator directory is left
behind, runs `plutil`, checks an invalid manifest returns nonzero with its
diagnostic on stderr and without creating output, proves an existing output
directory is not modified, builds the `IonStudio` target and its dependency
with `xcodebuild`, and smoke-runs both apps with their plugin bundle
identifiers.

The Recompiler candidate must independently pass its Raiser tests, full compiler
suite, corpus regression comparison and sanitizer corpus. Ion's test script is
a consumer gate, not a substitute for compiler verification.

## Current boundary

- The emitter supports macOS application targets only. `Platform.Ios` exists in
  the model for evolution, but the emitter rejects it explicitly.
- Debug and Release Xcode configurations currently invoke the same compiler
  command. Release optimization policy is not defined yet.
- Manifests are trusted programs. Current Raiser host bindings expose filesystem
  and subprocess operations; there is no capability sandbox.
- Evaluation starts a fresh Raiser process for each generation. There is no
  persistent evaluator, hot reload or manifest cache.
- `ion-generate` is a separate proof-of-concept binary and is not wired into the
  existing `bin/ion` packaging CLI.
- Generated apps are unsigned development products. Signing, notarization,
  assets and distribution packaging remain in Ion's existing packaging layer.
- The generated project embeds absolute source and compiler paths. Regenerate
  after moving the checkout or changing the compiler binary.
- PBX object identifiers are derived from target and dependency positions.
  Output is byte-identical for the same manifest, but reordering targets
  renumbers objects.
- Plugins contribute bundle identifiers only. Settings, files and new targets
  are not contribution kinds yet.

The next product step is to stabilize the project-description package and fold
the generator command into Ion's primary CLI without moving graph or emitter
responsibilities into Neon or Recompiler.
