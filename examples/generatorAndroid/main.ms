@passL("-llog");

import { ionFixtureRun, ionFixtureAsset } from "./fixture.h";
import { readResource } from "../../src/window";
import { androidLibrary } from "../../src/android";

when (android) {
	androidLibrary("./android");
}

function resource(path: string): string {
	const read = readResource(path);
	return read.ok ? read.value.asString().trim() : read.error;
}

ionFixtureAsset(`marker=${resource("assets/marker.txt")} nested=${resource("bundle/nested/inner.txt")} missing=${resource("assets/none.txt")}`);
ionFixtureRun(0);
