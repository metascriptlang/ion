import os
from pathlib import Path
import subprocess
import sys

repo = Path(__file__).resolve().parents[3]
results = Path(sys.argv[1]).resolve()
results.mkdir(parents=True, exist_ok=True)
generator = ["bash", str(repo / "tooling/generator/ion-generate")]


def generate(name, manifest, output, expected):
    result = subprocess.run([*generator, str(manifest), str(output)], cwd=repo,
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    (results / (name + ".log")).write_text(result.stdout + result.stderr)
    if result.returncode != expected:
        raise RuntimeError(f"{name}: exit {result.returncode}, expected {expected}\n"
                           + result.stdout + result.stderr)


def tree(root):
    return {path.relative_to(root).as_posix(): path.read_bytes()
            for path in root.rglob("*") if path.is_file()}


first = results / "first"
second = results / "second"
generate("first", "examples/generator/project.ms", first.as_posix(), 0)
generate("second", "examples/generator/project.ms", os.path.relpath(second, repo), 0)
original = tree(first)
assert original == tree(second), "fresh processes produced different projects"
generate("overwrite", "examples/generator/project.ms", first, 1)
assert tree(first) == original, "overwrite refusal changed the existing project"
invalid = results / "invalid"
generate("invalid", "tooling/generator/tests/invalid.ms", invalid, 1)
assert not invalid.exists(), "invalid manifest created output"
android = results / "android nested" / "output with spaces"
generate("android", repo / "examples/generatorAndroid/project.ms", android, 0)
print("PASS: generator fresh-process determinism, relative and absolute native paths, "
      "overwrite preservation, invalid-manifest isolation, nested Android output with spaces (5 invocations)")
print(f"generator logs={results}")
