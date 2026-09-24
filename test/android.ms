import { androidLibrary } from "../src/android";

const library: string = androidLibrary("./androidLibrary");

test "androidLibrary resolves the module beside the calling file" {
	assert library.endsWith("/test/androidLibrary");
}
