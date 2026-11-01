// Tests for src/platform/common/protoReg.{c,h}: the schemes a webview installs, and what asset://
// answers: 404 is a path the scope allows that names no file.

@compile("../../src/platform/common/protoReg.c");
@compile("../../src/platform/common/mime.c");
@compile("./protoRegHelper.c");
@include("../../src/platform/common/protoReg.h");
@include("./protoRegHelper.h");

extern function ionProtoRegister(scheme: cstring, baseDir: cstring): int32;
extern function ionProtoRegisterAsset(roots: cstring): int32;
extern function ionProtoSchemeCount(): int32;
extern function ionProtoSchemeAt(i: int32): cstring;
extern function ionProtoResetForTests(): void;
extern function ionTestProtoStatus(scheme: cstring, rawPath: cstring): int32;

const OK: int32 = 0 as int32;
const DUPLICATE: int32 = 5 as int32;

function schemes(): string {
	let out = "";
	for (let i = 0; i < ionProtoSchemeCount(); i++) out += `${ionProtoSchemeAt(i as int32) as string} `;
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

test "asset serves a file under its root and refuses one outside" {
	ionProtoResetForTests();
	assert ionProtoRegisterAsset("/tmp\nsrc") === OK;
	assert ionTestProtoStatus("asset", "/tmp") === 404;
	assert ionTestProtoStatus("asset", "/etc/hosts") === 403;
	assert ionTestProtoStatus("asset", "/tmp/../etc/hosts") === 403;
	assert ionTestProtoStatus("asset", "/tmpx/a") === 403;
}

test "a drive-letter URL path drops its leading slash and matches either separator" {
	ionProtoResetForTests();
	assert ionProtoRegisterAsset("C:\\Users\\me\\assets") === OK;
	assert ionTestProtoStatus("asset", "/C:/Users/me/assets/missing.txt") === 404;
	assert ionTestProtoStatus("asset", "/C%3A%5CUsers%5Cme%5Cassets%5Cmissing.txt") === 404;
	assert ionTestProtoStatus("asset", "/C:/Users/me/other.txt") === 403;
}
