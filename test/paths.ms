import { appIdentifier, appDataDir } from "../src/paths";
import { homeDir } from "std/os";

test "an unbundled program is identified by its name" {
	assert appIdentifier() !== "";
	assert !appIdentifier().includes("/") && !appIdentifier().endsWith(".exe");
}

test "the app data directory ends with the identifier" {
	const dir = appDataDir();
	assert dir.ok && dir.value.endsWith(appIdentifier());
}

when (macos) {
	test "on macOS it sits in Application Support" {
		const dir = appDataDir();
		assert dir.ok && dir.value == homeDir() + "/Library/Application Support/" + appIdentifier();
	}
}
