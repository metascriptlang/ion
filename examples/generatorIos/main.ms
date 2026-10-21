import { resourcePath } from "../../src/window";
import { readFile } from "std/fs";
import { join } from "std/fs/path";

@include("./fixture.h");
@compile("./host.m", "-fobjc-arc");
@passL("-framework UIKit");
@passL("-framework Foundation");

extern function ionFixtureRun(value: int32): void;
extern function ionFixtureAsset(found: int32): void;

const asset = readFile(join(resourcePath(), "assets/marker.txt"));
ionFixtureAsset(asset.ok && asset.value == "ion asset\n" ? 1 as int32 : 0 as int32);
ionFixtureRun(0);
