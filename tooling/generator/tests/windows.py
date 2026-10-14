import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

repo = Path(__file__).resolve().parents[3]
results = Path(sys.argv[1]).resolve() / "windows"
results.mkdir(parents=True, exist_ok=True)
manifest = repo / "examples/helloWebviewProject.ms"
targets = ["IonHello", "IonPreview"]


def run(name, command, expected=0, cwd=repo):
    result = subprocess.run(command, cwd=cwd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (results / (name + ".log")).write_text(result.stdout, encoding="utf-8")
    if result.returncode != expected:
        raise RuntimeError(f"{name}: exit {result.returncode}, expected {expected}\n{result.stdout[-3000:]}")
    return result.stdout


def tree(root):
    return {path.relative_to(root).as_posix(): path.read_bytes() for path in root.rglob("*") if path.is_file()}


def msbuild():
    vswhere = Path(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")) / "Microsoft Visual Studio/Installer/vswhere.exe"
    found = subprocess.run([str(vswhere), "-latest", "-products", "*", "-requires", "Microsoft.Component.MSBuild",
                            "Microsoft.VisualStudio.Component.VC.Tools.x86.x64", "-find", r"MSBuild\**\Bin\amd64\MSBuild.exe"],
                           text=True, stdout=subprocess.PIPE, check=True).stdout.splitlines()
    if not found:
        raise RuntimeError("no MSBuild with the x64 VC tools; install Visual Studio Build Tools")
    return found[0]


def build(name, solution, configuration, expected=0):
    return run(name, [msbuild(), str(solution), f"-p:Configuration={configuration}", "-p:Platform=x64",
                      "-nologo", "-v:minimal"], expected)


def git_status():
    return subprocess.run(["git", "status", "--porcelain", "--ignored"], cwd=repo, text=True,
                          stdout=subprocess.PIPE, check=True).stdout


source_before = git_status()
generator = ["bash", str(repo / "tooling/generator/ion-generate")]
project = results / "generated project"
second = results / "second"
shutil.rmtree(project, ignore_errors=True)
shutil.rmtree(second, ignore_errors=True)
run("generate", [*generator, str(manifest), str(project)])
run("generate-second", [*generator, os.path.relpath(manifest, repo), os.path.relpath(second, repo)])
assert tree(project) == tree(second), "fresh processes produced different projects"
shutil.rmtree(second)

solution = project / "IonHello.sln"
for configuration in ["Debug", "Release"]:
    build("build-" + configuration, solution, configuration)
    for target in targets:
        product = project / "bin" / target / configuration
        for name in [target + ".exe", "WebView2Loader.dll", "resources/hello.html"]:
            assert (product / name).is_file(), f"{configuration} {target} lacks {name}"
assert (project / "bin/IonHello/Release/IonHello.exe").stat().st_size < (project / "bin/IonHello/Debug/IonHello.exe").stat().st_size, \
    "Release did not pass --release"

app = project / "bin/IonHello/Debug/IonHello.exe"
log = results / "app.out"
elsewhere = results / "elsewhere"
elsewhere.mkdir(exist_ok=True)
with open(log, "w", encoding="utf-8") as out:
    process = subprocess.Popen([str(app)], cwd=elsewhere, stdout=out, stderr=subprocess.STDOUT)
    try:
        deadline = time.time() + 30
        while time.time() < deadline and "auto-call addNumbers result: 123" not in log.read_text(encoding="utf-8", errors="replace"):
            time.sleep(0.5)
    finally:
        process.kill()
        process.wait()
output = log.read_text(encoding="utf-8", errors="replace")
for line in ["auto-probe: ipc alive", "MS command addNumbers(100, 23)", "auto-call addNumbers result: 123"]:
    assert line in output, f"app launched from another directory did not log {line!r}:\n{output}"

fixture_app = results / "fixture app"
fixture_project = results / "fixture project"
shutil.rmtree(fixture_app, ignore_errors=True)
shutil.rmtree(fixture_project, ignore_errors=True)
(fixture_app / "lib").mkdir(parents=True)
(fixture_app / "build.ms").write_text(
    'const config = {\n\tglobalImports: ["./lib/greet"],\n};\nexport default config;\n', encoding="utf-8")
(fixture_app / "lib/greet.ms").write_text(
    'export function greet(name: string): string {\n\treturn "hello " + name;\n}\n', encoding="utf-8")
entry = fixture_app / "main.ms"
entry.write_text('console.log(greet("ion"));\n', encoding="utf-8")
description = (repo / "tooling/generator/description").as_posix()
(fixture_app / "project.ms").write_text(
    f'import {{ Project, Target }} from "{description}";\n'
    'export const project: Project = {\n'
    '\tname: "Fixture",\n'
    '\ttargets: [{ ...Target.windowsApp("Fixture", "main.ms"), bundleId: "dev.ion.Fixture" }],\n'
    '\tplugins: [],\n'
    '};\n', encoding="utf-8")
run("generate-fixture", [*generator, str(fixture_app / "project.ms"), str(fixture_project)])
fixture_sln = fixture_project / "Fixture.sln"
fixture_exe = fixture_project / "bin/Fixture/Debug/Fixture.exe"
build("build-fixture", fixture_sln, "Debug")
greeting = run("run-fixture", [str(fixture_exe)])
assert "hello ion" in greeting, f"the entry did not see its build.ms globalImports:\n{greeting}"
assert not (fixture_app / "out").exists(), "msc wrote its out/ into the app source tree"

marker = "RelinkMarker".encode("utf-16-le")
assert marker not in fixture_exe.read_bytes(), "marker present before the .rc changed"
rc = fixture_project / "Fixture/Fixture.rc"
text = rc.read_text(encoding="utf-8")
assert 'VALUE "ProductName", "Fixture"' in text
rc.write_text(text.replace('VALUE "ProductName", "Fixture"', 'VALUE "ProductName", "RelinkMarker"'), encoding="utf-8")
build("build-relink", fixture_sln, "Debug")
assert marker in fixture_exe.read_bytes(), "a changed .res did not relink the executable"

original = entry.read_bytes()
entry.write_bytes(original + b'const broken: int32 = "x";\n')
build("build-broken", fixture_sln, "Debug", expected=1)
assert not fixture_exe.exists(), "a failed msc build left a runnable executable"
entry.write_bytes(original)
build("build-recovered", fixture_sln, "Debug")
assert fixture_exe.is_file(), "the fixed source did not rebuild"

(project / "bin/IonHello/Debug/resources/stale.txt").write_text("stale")
build("build-again", solution, "Debug")
assert not (project / "bin/IonHello/Debug/resources/stale.txt").exists(), "a removed asset survived the build"

assert git_status() == source_before, "the build wrote into the source tree:\n" + git_status()
print("PASS: Windows generation determinism, MSBuild Debug and Release with a dependency, product layout, "
      "launch from another directory with IPC, app build.ms globalImports in effect, changed .rc relinks, "
      "failed build leaves no executable, recovery, stale asset removal, "
      "source tree untouched")
print(f"windows logs={results}")
