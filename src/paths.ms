// Where an app keeps its own data, as Tauri's `app_data_dir`: the OS data directory of the
// `dirs` crate joined with the app's identifier. The directory is not created.
//
//   macOS    ~/Library/Application Support/<bundle id>
//   Windows  %APPDATA%\<executable name>
//   Linux    $XDG_DATA_HOME/<executable name>, else ~/.local/share/<executable name>
when (macos) {
	@compile("./platform/macos/core/paths.m", "-fobjc-arc");
	@passL("-framework Foundation");
}

when (windows) {
	@compile("./platform/windows/core/paths.c");
	@compile("./platform/windows/utf8.c");
}

when (linux) {
	@compile("./platform/linux/core/paths.c");
}

import { ionAppIdentifier } from "./platform/bridge.h";
import { env, platform } from "std/process";
import { homeDir } from "std/os";
import { join } from "std/fs/path";

// The bundle id on macOS, or the process name when the app runs unbundled; the executable's name
// on Windows (without ".exe") and Linux.
export function appIdentifier(): string {
	return ionAppIdentifier();
}

function dataDir(): string {
	if (platform === "darwin") return join(homeDir(), "Library/Application Support");
	if (platform === "windows") return env.get("APPDATA") ?? "";
	const xdg = env.get("XDG_DATA_HOME") ?? "";
	if (xdg.startsWith("/")) return xdg;
	const home = homeDir();
	return home === "" ? "" : join(home, ".local/share");
}

export function appDataDir(): Result<string, string> {
	const id = appIdentifier();
	if (id === "") return Result.err("appDataDir: the OS gives no app identifier");
	const base = dataDir();
	if (base === "") return Result.err("appDataDir: no data directory for " + platform);
	return Result.ok(join(base, id));
}
