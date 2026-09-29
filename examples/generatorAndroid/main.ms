@passL("-llog");

import { ionFixtureRun } from "./fixture.h";
import { androidLibrary } from "../../src/android";

when (android) {
	androidLibrary("./android");
}

ionFixtureRun(0);
