import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

repo = Path(__file__).resolve().parents[3]
results = Path(sys.argv[1]) / "android with spaces"
results.mkdir()
source = results / "source with spaces"
shutil.copytree(repo / "examples/generatorAndroid", source)
manifest = source / "project.ms"
manifest.write_text(manifest.read_text().replace("../../tooling/generator/", str(repo / "tooling/generator") + "/"))
sdk = Path(os.environ.get("ANDROID_HOME") or Path.home() / "Library/Android/sdk")
ndk_bin = sdk / "ndk/28.0.13004108/toolchains/llvm/prebuilt/darwin-x86_64/bin"
build_tools = sdk / "build-tools/36.0.0"
adb = sdk / "platform-tools/adb"
package = "dev.ion.IonAndroid"
activity = package + "/dev.metascript.app.MainActivity"
sequence = 0


def run(name, args, *, env=None, cwd=repo, success=True):
    global sequence
    sequence += 1
    result = subprocess.run([str(arg) for arg in args], cwd=cwd, env=env,
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    log = results / f"{sequence:02d}-{name}.log"
    log.write_text(result.stdout)
    if (result.returncode == 0) != success:
        raise RuntimeError(f"{name}: exit {result.returncode}; {log}\n" +
                           "\n".join(result.stdout.splitlines()[-15:]))
    return result.stdout


def tree(root):
    return {str(path.relative_to(root)): path.read_bytes()
            for path in sorted(root.rglob("*")) if path.is_file()}


generator = repo / "tooling/generator/ion-generate"
for name in ("first", "second"):
    run("generate-" + name, [generator, manifest, results / name])
project = results / "first"
assert tree(project) == tree(results / "second"), "fresh generations differ"
assert os.access(project / "gradlew", os.X_OK)
vendored = repo / "tooling/generator/android/wrapper/gradle-wrapper.jar"
assert (project / "gradle/wrapper/gradle-wrapper.jar").read_bytes() == vendored.read_bytes()
assert hashlib.sha256(vendored.read_bytes()).hexdigest() == \
    "b3a875ddc1f044746e1b1a55f645584505f4a10438c1afea9f15e92a7c42ec13"
assert not [p for p in tree(project) if p.endswith((".c", ".h", ".cpp", "CMakeLists.txt", ".mk"))]
generated = tree(project)

refused = run("overwrite", [generator, manifest, project], success=False)
assert "output already exists" in refused
assert tree(project) == generated
invalid = source / "invalid.ms"
invalid.write_text(manifest.read_text().replace(
    'targets: [Target.androidApp("IonAndroid", "main.ms")]',
    'targets: [{ ...Target.androidApp("IonAndroid", "main.ms"), android: '
    '{ ...Target.androidApp("IonAndroid", "main.ms").android, minSdk: 21 } }]'))
rejected = run("invalid", [generator, invalid, results / "invalid"], success=False)
assert "needs minSdk >= 23, got 21" in rejected
assert not (results / "invalid").exists()
invalid.unlink()

gradle_env = {key: value for key, value in os.environ.items() if not key.startswith("ION_ANDROID_")}


def gradle(name, *tasks, success=True, env=None):
    return run(name, [project / "gradlew", "--no-daemon", "--console=plain", *tasks],
               cwd=project, env=env or gradle_env, success=success)


outputs = project / "app/build/outputs"
debug_apk = outputs / "apk/debug/app-debug.apk"
release_apk = outputs / "apk/release/app-release.apk"
release_aab = outputs / "bundle/release/app-release.aab"
libraries = project / "app/build/generated/jniLibs"


def library(variant):
    return libraries / f"compileMetaScript{variant}/arm64-v8a/libmetascript.so"


def inspect(variant):
    path = library(variant)
    exports = run("nm-" + variant, [ndk_bin / "llvm-nm", "-D", "--defined-only", path])
    for symbol in ("MsMain", "Java_dev_metascript_app_NativeApp_start", "Java_dev_metascript_app_NativeApp_resize",
                   "Java_dev_metascript_app_NativeApp_pause", "Java_dev_metascript_app_NativeApp_resume",
                   "Java_dev_metascript_app_NativeApp_destroy"):
        assert re.search(rf"\b{symbol}$", exports, re.M), f"{variant} misses {symbol}"
    segments = run("readelf-" + variant, [ndk_bin / "llvm-readelf", "-lW", path])
    loads = [line.split()[-1] for line in segments.splitlines() if line.split()[:1] == ["LOAD"]]
    assert loads and all(align == "0x4000" for align in loads), f"{variant} PT_LOAD alignment {loads}"
    sections = run("sections-" + variant, [ndk_bin / "llvm-readelf", "-SW", path])
    return ".symtab" in sections


gradle("debug", "assembleDebug")
assert inspect("Debug"), "Debug library lost its symbols"
run("zipalign-debug", [build_tools / "zipalign", "-c", "-P", "16", "-v", "4", debug_apk])
assert (project / "app/build/metascript/debug").is_dir()

missing = gradle("release-unsigned", "assembleRelease", success=False)
assert "Release signing is missing ION_ANDROID_STORE_FILE" in missing
assert not library("Release").exists(), "unsigned release compiled native code"
assert not release_apk.exists()

keystore = results / "release key.jks"
run("keytool", ["keytool", "-genkeypair", "-keystore", keystore, "-storepass", "ion-store", "-keypass", "ion-store",
                "-alias", "ion", "-keyalg", "RSA", "-keysize", "2048", "-validity", "2",
                "-dname", "CN=Ion generator fixture"])
signed_env = dict(gradle_env, ION_ANDROID_STORE_FILE=str(keystore), ION_ANDROID_STORE_PASSWORD="ion-store",
                  ION_ANDROID_KEY_ALIAS="ion", ION_ANDROID_KEY_PASSWORD="ion-store")
gradle("release", "assembleRelease", "bundleRelease", env=signed_env)
assert not inspect("Release"), "Release library is not stripped"
assert (project / "app/build/metascript/release").is_dir()
assert library("Debug").read_bytes() != library("Release").read_bytes()
certificate = run("apksigner", [build_tools / "apksigner", "verify", "--verbose", "--print-certs", release_apk])
assert "CN=Ion generator fixture" in certificate
run("zipalign-release", [build_tools / "zipalign", "-c", "-P", "16", "-v", "4", release_apk])
assert "jar verified." in run("jarsigner", ["jarsigner", "-verify", release_aab])
for secret in ("ion-store",):
    assert not [p for p, content in tree(project).items() if not p.startswith(("app/build", "build", ".gradle"))
                and secret.encode() in content], "signing secret leaked into the project"

emulator = None
if not os.environ.get("ANDROID_SERIAL") and "emulator-" not in run("devices", [adb, "devices"]):
    os.environ["ANDROID_SERIAL"] = "emulator-5554"
    avd = os.environ.get("ION_ANDROID_AVD", "Pixel_9_Pro")
    emulator = subprocess.Popen([sdk / "emulator/emulator", "-avd", avd, "-no-window", "-no-audio",
                                 "-no-snapshot-save", "-no-boot-anim"],
                                stdout=(results / "emulator.log").open("w"), stderr=subprocess.STDOUT)
try:
    run("wait-device", [adb, "wait-for-device"])
    deadline = time.monotonic() + 300
    while subprocess.run([str(adb), "shell", "getprop", "sys.boot_completed"],
                         capture_output=True, text=True).stdout.strip() != "1":
        if time.monotonic() > deadline:
            raise RuntimeError("emulator did not boot")
        time.sleep(2)
    assert run("sdk", [adb, "shell", "getprop", "ro.build.version.sdk"]).strip() == "36"
    rotation = {key: run("setting-" + key, [adb, "shell", "settings", "get", "system", key]).strip()
                for key in ("accelerometer_rotation", "user_rotation")}
    run("rotation-lock", [adb, "shell", "settings", "put", "system", "accelerometer_rotation", "0"])
    run("portrait-start", [adb, "shell", "settings", "put", "system", "user_rotation", "0"])

    def events():
        return re.findall(r"IonFixture: (.*)", run("logcat", [adb, "logcat", "-d", "-s", "IonFixture"]))

    def launch(apk, expected):
        subprocess.run([str(adb), "uninstall", package], capture_output=True)
        run("install", [adb, "install", apk])
        run("logcat-clear", [adb, "logcat", "-c"])
        run("launch", [adb, "shell", "am", "start", "-W", "-n", activity])
        deadline = time.monotonic() + 30
        text = f'text="Ion Android native value: {expected}"'
        while True:
            run("ui-dump", [adb, "shell", "uiautomator", "dump", "/sdcard/ion-android.xml"])
            ui = run("ui", [adb, "exec-out", "cat", "/sdcard/ion-android.xml"])
            if text in ui:
                break
            if time.monotonic() > deadline:
                raise RuntimeError(f"expected native value {expected}; logs={results}")
            time.sleep(1)
        assert package not in run("crash", [adb, "logcat", "-d", "-b", "crash"])
        (results / f"{sequence:02d}-launched-value.txt").write_text(text)

    def settle(expected, timeout=15):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            seen = events()
            if expected(seen):
                return seen
            time.sleep(0.5)
        raise RuntimeError(f"lifecycle did not settle; saw {events()}; logs={results}")

    def pid():
        return run("pid", [adb, "shell", "pidof", package]).strip()

    launch(debug_apk, 17)
    first = settle(lambda seen: any(e.startswith("resize ") for e in seen))
    assert first[0] == "start value=17" and "resume value=17" in first
    width, height = map(int, re.search(r"resize (\d+)x(\d+)", " ".join(first)).groups())
    process = pid()
    run("logcat-clear", [adb, "logcat", "-c"])
    run("landscape", [adb, "shell", "settings", "put", "system", "user_rotation", "1"])
    settle(lambda seen: f"resize {height}x{width} value=17" in seen)
    run("portrait", [adb, "shell", "settings", "put", "system", "user_rotation", "0"])
    settle(lambda seen: f"resize {width}x{height} value=17" in seen)
    run("home", [adb, "shell", "input", "keyevent", "KEYCODE_HOME"])
    settle(lambda seen: seen[-1] == "pause value=17")
    run("relaunch", [adb, "shell", "am", "start", "-W", "-n", activity])
    settle(lambda seen: seen[-1] == "resume value=17")
    assert pid() == process, "lifecycle crossed processes"
    task = re.search(r"taskId=(\d+): " + re.escape(activity), run("stacks", [adb, "shell", "am", "stack", "list"]))
    run("remove-task", [adb, "shell", "am", "stack", "remove", task.group(1)])
    lifecycle = settle(lambda seen: seen[-1] == "destroy value=17")
    assert "start value=17" not in lifecycle, "size change recreated the activity"
    with (results / "device.png").open("wb") as screenshot:
        subprocess.run([str(adb), "exec-out", "screencap", "-p"], stdout=screenshot, check=True)

    launch(release_apk, 17)

    fixture = source / "fixture.c"
    header = source / "fixture.h"
    fixture.write_text(fixture.read_text().replace("ION_FIXTURE_VALUE + 0", "ION_FIXTURE_VALUE + 10"))
    gradle("native-source-edit", "assembleDebug")
    launch(debug_apk, 27)
    header.write_text(header.read_text().replace("ION_FIXTURE_VALUE 17", "ION_FIXTURE_VALUE 23"))
    gradle("native-header-edit", "assembleDebug")
    launch(debug_apk, 33)
    fixture.write_text(fixture.read_text() + "\n#error Ion fixture deliberate native failure\n")
    gradle("native-failure", "assembleDebug", success=False)
    assert not library("Debug").exists(), "failed compile left a native library"
    assert not debug_apk.exists(), "failed compile left a runnable stale APK"
    fixture.write_text(fixture.read_text().replace("\n#error Ion fixture deliberate native failure\n", ""))
    gradle("native-recovery", "assembleDebug")
    launch(debug_apk, 33)
    for path, content in generated.items():
        assert (project / path).read_bytes() == content, f"build rewrote generated {path}"
    assert not (source / "out").exists(), "Gradle build polluted the shared source tree"
finally:
    for key, value in locals().get("rotation", {}).items():
        subprocess.run([str(adb), "shell", "settings", "put", "system", key, value], capture_output=True)
    subprocess.run([str(adb), "uninstall", package], capture_output=True)
    if emulator:
        subprocess.run([str(adb), "emu", "kill"], capture_output=True)
        emulator.wait(timeout=60)

print("PASS: Android deterministic generation, vendored wrapper, overwrite and invalid-manifest refusal, "
      "Debug/Release separation, 16 KiB ELF/APK alignment, signed APK/AAB, missing-signing refusal, "
      "JNI lifecycle on Android 36 (" + os.environ["ANDROID_SERIAL"] + "), spaced paths, source/header rebuilds and failure recovery")
print(f"android logs={results}")
