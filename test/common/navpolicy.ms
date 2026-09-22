// Tests for src/platform/common/navpolicy.{c,h}.
// Pure decision function — no platform deps.

@compile("../../src/platform/common/navpolicy.c");
@include("../../src/platform/common/navpolicy.h");

extern function ion_nav_decide(scheme: cstring, host: cstring, isUserClick: int32): int32;

const ALLOW:    int32 = 0 as int32;
const EXTERNAL: int32 = 1 as int32;
const BLOCK:    int32 = 2 as int32;

test "file:// always blocked" {
	assert ion_nav_decide("file", "", 0 as int32) === BLOCK;
	assert ion_nav_decide("file", "", 1 as int32) === BLOCK;
}

test "about: always allowed" {
	assert ion_nav_decide("about", "", 0 as int32) === ALLOW;
}

test "data: always allowed" {
	assert ion_nav_decide("data", "", 1 as int32) === ALLOW;
}

test "localhost http always allowed (dev server)" {
	assert ion_nav_decide("http",  "localhost", 1 as int32) === ALLOW;
	assert ion_nav_decide("https", "localhost", 1 as int32) === ALLOW;
}

test "127.0.0.1 always allowed" {
	assert ion_nav_decide("http", "127.0.0.1", 1 as int32) === ALLOW;
}

test "::1 always allowed" {
	assert ion_nav_decide("http", "::1", 1 as int32) === ALLOW;
}

test "user-clicked external https → external" {
	assert ion_nav_decide("https", "github.com", 1 as int32) === EXTERNAL;
}

test "user-clicked external http → external" {
	assert ion_nav_decide("http", "example.com", 1 as int32) === EXTERNAL;
}

test "user-clicked mailto → external" {
	assert ion_nav_decide("mailto", "", 1 as int32) === EXTERNAL;
}

test "programmatic external https → allow (SPA routing)" {
	assert ion_nav_decide("https", "github.com", 0 as int32) === ALLOW;
}

test "scheme is case-insensitive" {
	assert ion_nav_decide("FILE", "", 0 as int32) === BLOCK;
	assert ion_nav_decide("HTTPS", "github.com", 1 as int32) === EXTERNAL;
}

test "host is case-insensitive (LOCALHOST)" {
	assert ion_nav_decide("http", "LOCALHOST", 1 as int32) === ALLOW;
}

test "empty scheme → allow (defensive)" {
	assert ion_nav_decide("", "", 0 as int32) === ALLOW;
}

test "unknown scheme → allow (don't break SPA)" {
	assert ion_nav_decide("custom-app", "", 1 as int32) === ALLOW;
}
