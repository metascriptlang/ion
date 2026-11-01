import { openExternal } from "../src/shell";

test "an empty URL is not opened" {
	assert !openExternal("");
}

test "a URL that does not parse is not opened" {
	assert !openExternal("not a url");
}
