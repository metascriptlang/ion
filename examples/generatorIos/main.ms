import { readResource } from "../../src/window";

@include("./fixture.h");
@compile("./host.m", "-fobjc-arc");
@passL("-framework UIKit");
@passL("-framework Foundation");

extern function ionFixtureRun(value: int32): void;
extern function ionFixtureAsset(found: int32): void;

const asset = readResource("assets/marker.txt");
const nested = readResource("bundle/nested/inner.txt");
const found = asset.ok && asset.value.asString() == "ion asset\n" && nested.ok && nested.value.asString() == "nested asset\n";
ionFixtureAsset(found ? 1 as int32 : 0 as int32);
ionFixtureRun(0);
