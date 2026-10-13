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

wrapper = project / "IonPreview/IonPreview.ms"
original = wrapper.read_bytes()
wrapper.write_bytes(original + b'const broken: int32 = "x";\n')
build("build-broken", project / "IonPreview/IonPreview.vcxproj", "Debug", expected=1)
assert not (project / "bin/IonPreview/Debug/IonPreview.exe").exists(), "a failed msc build left a runnable executable"
wrapper.write_bytes(original)
build("build-recovered", project / "IonPreview/IonPreview.vcxproj", "Debug")
assert (project / "bin/IonPreview/Debug/IonPreview.exe").is_file(), "the fixed source did not rebuild"

(project / "bin/IonHello/Debug/resources/stale.txt").write_text("stale")
build("build-again", solution, "Debug")
assert not (project / "bin/IonHello/Debug/resources/stale.txt").exists(), "a removed asset survived the build"

assert git_status() == source_before, "the build wrote into the source tree:\n" + git_status()
print("PASS: Windows generation determinism, MSBuild Debug and Release with a dependency, product layout, "
      "launch from another directory with IPC, failed build leaves no executable, recovery, stale asset removal, "
      "source tree untouched")
print(f"windows logs={results}")
