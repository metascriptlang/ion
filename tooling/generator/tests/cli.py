import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

repo = Path(__file__).resolve().parents[3]
results = Path(sys.argv[1]).resolve()
results.mkdir(parents=True, exist_ok=True)
generator = ["bash", str(repo / "tooling/generator/ion-generate")]


def evaluators():
    roots = {tempfile.gettempdir(), *(os.environ.get(n, "") for n in ("TMPDIR", "TEMP", "TMP")), "/tmp"}
    return sorted(str(p) for r in roots if r and Path(r).is_dir() for p in Path(r).glob("ion-generator.*"))


def generate(name, manifest, output, expected, cwd=repo):
    arguments = [] if manifest is None else [str(manifest), str(output)]
    result = subprocess.run([*generator, *arguments], cwd=cwd,
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    (results / (name + ".log")).write_text(result.stdout + result.stderr)
    if result.returncode != expected:
        raise RuntimeError(f"{name}: exit {result.returncode}, expected {expected}\n"
                           + result.stdout + result.stderr)


def tree(root):
    return {path.relative_to(root).as_posix(): path.read_bytes()
            for path in root.rglob("*") if path.is_file()}


leftover = evaluators()
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
default = repo / "examples/generator/out/xcode"
shutil.rmtree(default, ignore_errors=True)
generate("default", None, None, 0, cwd=repo / "examples/generator")
assert tree(default) == original, "default manifest and output differ from the explicit run"
shutil.rmtree(default)
assert evaluators() == leftover, "an evaluator directory was left behind"
print("PASS: generator fresh-process determinism, relative and absolute native paths, "
      "overwrite preservation, invalid-manifest isolation, nested Android output with spaces, default manifest and output, no evaluator left behind (6 invocations)")
print(f"generator logs={results}")
