// Tests for src/platform/common/protoReg.{c,h}: the schemes a webview installs.

@compile("../../src/platform/common/protoReg.c");
@compile("../../src/platform/common/mime.c");
@include("../../src/platform/common/protoReg.h");

extern function ionProtoRegister(scheme: cstring, baseDir: cstring): int32;
extern function ionProtoRegisterAsset(roots: cstring): int32;
extern function ionProtoSchemeCount(): int32;
extern function ionProtoSchemeAt(i: int32): cstring;
extern function ionProtoResetForTests(): void;

const OK: int32 = 0 as int32;
const DUPLICATE: int32 = 5 as int32;

function schemes(): string {
	let out = "";
	for (let i = 0; i < ionProtoSchemeCount(); i++) out += `${ionProtoSchemeAt(i as int32)} `;
	return out;
}

test "the asset scope adds asset to the installed schemes" {
	ionProtoResetForTests();
	assert ionProtoRegisterAsset("/tmp") === OK;
	assert schemes() === "asset ";
}

test "asset follows the static protocols" {
	ionProtoResetForTests();
	assert ionProtoRegister("ion", "/tmp") === OK;
	assert ionProtoRegister("demo", "/tmp") === OK;
	assert ionProtoRegisterAsset("/tmp\n/var") === OK;
	assert schemes() === "ion demo asset ";
}

test "without a scope asset is not installed" {
	ionProtoResetForTests();
	assert ionProtoRegister("ion", "/tmp") === OK;
	assert schemes() === "ion ";
}

test "a static protocol cannot take the asset scheme" {
	ionProtoResetForTests();
	assert ionProtoRegister("Asset", "/tmp") === DUPLICATE;
	assert schemes() === "";
}
