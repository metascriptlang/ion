@include("./fixture.h");
@compile("./host.m", "-fobjc-arc");
@passL("-framework UIKit");
@passL("-framework Foundation");

extern function ionFixtureRun(value: int32): void;
ionFixtureRun(0);
