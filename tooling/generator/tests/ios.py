import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import time

repo = Path(__file__).resolve().parents[3]
results = Path(sys.argv[1]) / "ios with spaces"
results.mkdir()
source = results / "source with spaces"
shutil.copytree(repo / "examples/generatorIos", source)
manifest = source / "project.ms"
manifest.write_text(manifest.read_text().replace("../../tooling/generator/", str(repo / "tooling/generator") + "/"))
sequence = 0


def run(name, args, *, env=None, success=True):
    global sequence
    sequence += 1
    result = subprocess.run([str(arg) for arg in args], cwd=repo, env=env,
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    log = results / f"{sequence:02d}-{name}.log"
    log.write_text(result.stdout)
    if (result.returncode == 0) != success:
        raise RuntimeError(f"{name}: exit {result.returncode}; {log}\n" +
                           "\n".join(result.stdout.splitlines()[-15:]))
    return result.stdout


generator = repo / "tooling/generator/ion-generate"
for name in ("first", "second"):
    run("generate-" + name, [generator, manifest, results / name])
project = results / "first/IonIos.xcodeproj"
pbx = project / "project.pbxproj"
for relative in ("graph.json", "IonIos.xcodeproj/project.pbxproj"):
    assert (results / "first" / relative).read_bytes() == (results / "second" / relative).read_bytes()
run("plutil", ["plutil", "-lint", pbx])
objects = json.loads(run("pbx-json", ["plutil", "-convert", "json", "-o", "-", pbx]))["objects"]
phases = [obj for obj in objects.values() if obj["isa"] == "PBXShellScriptBuildPhase"]
assert len(phases) == 1
assert not any(obj["isa"] in ("PBXSourcesBuildPhase", "PBXBuildFile") for obj in objects.values())
script = results / "buildNative.sh"
script.write_text(phases[0]["shellScript"])
products = results / "products with spaces"
base = ["xcodebuild", "-project", project, "-target", "IonIos", "-jobs", "1",
        "ARCHS=arm64", "ONLY_ACTIVE_ARCH=YES", f"SYMROOT={products}",
        f"OBJROOT={results / 'objects with spaces'}"]


def build(name, configuration="Debug", sdk="iphonesimulator", *, success=True, settings=()):
    return run(name, base + ["-configuration", configuration, "-sdk", sdk, *settings, "build"],
               success=success)


def bundle(configuration="Debug", sdk="iphonesimulator"):
    return products / f"{configuration}-{sdk}/IonIos.app"


def metadata(configuration, sdk, platform):
    app = bundle(configuration, sdk)
    with (app / "Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    assert info["CFBundleIdentifier"] == "dev.ion.IonIos"
    assert info["MinimumOSVersion"] == "15.0"
    assert info["UIDeviceFamily"] == [1, 2]
    assert "UILaunchScreen" in info
    output = run("macho-" + sdk + "-" + configuration,
                 ["xcrun", "vtool", "-show-build", app / "IonIos"])
    assert f"platform {platform}" in output
    assert "minos 15.0" in output


build("simulator-debug")
metadata("Debug", "iphonesimulator", "IOSSIMULATOR")
build("simulator-release", "Release")
metadata("Release", "iphonesimulator", "IOSSIMULATOR")
build("device-unsigned", sdk="iphoneos")
metadata("Debug", "iphoneos", "IOS")
build("simulator-signed", settings=("CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_IDENTITY=-"))
run("verify-signature", ["codesign", "--verify", "--strict", "--verbose=2", bundle()])
signature = run("display-signature", ["codesign", "-dv", bundle()])
assert "Signature=adhoc" in signature

available = json.loads(run("simulators", ["xcrun", "simctl", "list", "devices", "available", "--json"]))
candidates = [(runtime, device) for runtime, devices in available["devices"].items()
              if ".iOS-" in runtime for device in devices]
if not candidates:
    raise RuntimeError("iOS fixture requires an installed iOS simulator runtime and device type")
runtime, model = candidates[-1]
device = run("create-simulator", ["xcrun", "simctl", "create", "Ion generator fixture",
                                  model["deviceTypeIdentifier"], runtime]).strip()
try:
    run("boot", ["xcrun", "simctl", "boot", device])
    run("boot-ready", ["xcrun", "simctl", "bootstatus", device, "-b"])

    def launch(expected, configuration="Debug"):
        run("install", ["xcrun", "simctl", "install", device, bundle(configuration)])
        container = Path(run("container", ["xcrun", "simctl", "get_app_container", device,
                                            "dev.ion.IonIos", "data"]).strip())
        marker = container / "Documents/ion-generator.txt"
        marker.unlink(missing_ok=True)
        run("launch", ["xcrun", "simctl", "launch", "--terminate-running-process", device,
                       "dev.ion.IonIos"])
        deadline = time.monotonic() + 30
        while not marker.exists() and time.monotonic() < deadline:
            time.sleep(0.1)
        actual = marker.read_text()
        (results / f"{sequence:02d}-launched-value.txt").write_text(actual)
        assert actual == f"Ion iOS generator\nNative value: {expected}", (
            f"expected native value {expected}, got {actual!r}; logs={results}")

    launch(17)
    run("screenshot", ["xcrun", "simctl", "io", device, "screenshot", results / "simulator.png"])
    launch(17, "Release")
    host = source / "host.m"
    header = source / "fixture.h"
    host.write_text(host.read_text().replace("ION_FIXTURE_VALUE + 0", "ION_FIXTURE_VALUE + 10"))
    build("native-source-edit")
    launch(27)
    header.write_text(header.read_text().replace("ION_FIXTURE_VALUE 17", "ION_FIXTURE_VALUE 23"))
    build("native-header-edit")
    launch(33)

    sdkroot = run("sdk-path", ["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"]).strip()
    archive = source / "libfixture.a"
    native = source / "archive.c"

    def replace_archive(value):
        native.write_text(f"int ionArchiveValue(void) {{ return {value}; }}\n")
        run("archive-compile", ["xcrun", "clang", "-target", "arm64-apple-ios15.0-simulator",
                                "-isysroot", sdkroot, "-c", native, "-o", source / "archive.o"])
        run("archive-replace", ["xcrun", "ar", "rcs", archive, source / "archive.o"])

    replace_archive(7)
    header.write_text(header.read_text() + "int32_t ionArchiveValue(void);\n")
    entry = source / "main.ms"
    entry.write_text(entry.read_text().replace("ionFixtureRun(0);", "ionFixtureRun(ionArchiveValue());") +
                     '\nextern function ionArchiveValue(): int32;\n' +
                     '@link("./libfixture.a");\n')
    build("archive-initial")
    launch(40)
    replace_archive(29)
    build("archive-replaced")
    launch(62)
    host.write_text(host.read_text() + "\n#error Ion fixture deliberate native failure\n")
    build("native-failure", success=False)
    assert not (bundle() / "IonIos").exists(), "failed compiler left a runnable stale executable"
    host.write_text(host.read_text().replace("\n#error Ion fixture deliberate native failure\n", ""))
    build("native-recovery")
    launch(62)

    script_env = dict(os.environ, PLATFORM_NAME="iphonesimulator", ARCHS="arm64",
                      CONFIGURATION="Debug", SDKROOT=sdkroot, IPHONEOS_DEPLOYMENT_TARGET="15.0",
                      TARGET_TEMP_DIR=str(results / "invalid temp"),
                      TARGET_BUILD_DIR=str(results / "invalid products"), EXECUTABLE_PATH="IonIos.app/IonIos")
    for key, value, diagnostic in (("PLATFORM_NAME", "watchos", "unsupported SDK platform"),
                                   ("CONFIGURATION", "Profile", "unsupported configuration"),
                                   ("ARCHS", "arm64 x86_64", "unsupported architecture set")):
        output = run("reject-" + key, ["/bin/sh", script], env=dict(script_env, **{key: value}), success=False)
        assert diagnostic in output
    assert pbx.read_bytes() == (results / "second/IonIos.xcodeproj/project.pbxproj").read_bytes()
    assert not (source / "out").exists(), "Xcode build polluted the shared source tree"
finally:
    run("shutdown", ["xcrun", "simctl", "shutdown", device])
    run("delete-simulator", ["xcrun", "simctl", "delete", device])

print("PASS: iOS deterministic generation, simulator Debug/Release launch, ad-hoc signing, unsigned device, metadata, spaced paths, source/header/archive rebuilds, failure propagation and environment rejection")
print(f"ios logs={results}")
