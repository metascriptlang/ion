// Tests for src/platform/common/webviewRegistry.{c,h}. The table is
// process-global: each test frees every slot first.

@compile("../../src/platform/common/webviewRegistry.c");
@compile("../../src/platform/common/queue.c");
@include("../../src/platform/common/webviewRegistry.h");
@include("../../src/platform/common/queue.h");
@include("../../src/platform/bridge.h");

extern function ion_webview_alloc(label: cstring, window: int32): int32;
extern function ion_webview_free(id: int32): void;
extern function ion_webview_find(label: cstring): int32;
extern function ion_webview_next(prev: int32): int32;
extern function ionFindWebview(label: cstring): int32;
extern function ionWebviewLabel(id: int32): string;
extern function ionWebviewWindow(id: int32): int32;
extern function ion_queue_push_w(webview: int32, name: cstring, payload: cstring): int32;
extern function ion_queue_pop(): int32;
extern function ionMessageWebviewId(): int32;

function reset(): void {
	for (let i = 0; i < 32; i++) ion_webview_free(i as int32);
	while (ion_queue_pop() === 1 as int32) {}
}

test "a label is unique and names its window" {
	reset();
	const a = ion_webview_alloc("docs", 3 as int32);
	assert a >= 0;
	assert ion_webview_alloc("docs", 0 as int32) === -1 as int32;
	assert ionFindWebview("docs") === a;
	assert ionWebviewLabel(a) === "docs";
	assert ionWebviewWindow(a) === 3 as int32;
}

test "an empty label and an unknown id are refused" {
	reset();
	assert ion_webview_alloc("", 0 as int32) === -1 as int32;
	assert ionWebviewLabel(7 as int32) === "";
	assert ionWebviewWindow(7 as int32) === -1 as int32;
	assert ion_webview_find("missing") === -1 as int32;
}

test "a freed slot frees its label and leaves iteration" {
	reset();
	const a = ion_webview_alloc("a", 0 as int32);
	const b = ion_webview_alloc("b", 0 as int32);
	ion_webview_free(a);
	assert ion_webview_find("a") === -1 as int32;
	assert ion_webview_next(-1 as int32) === b;
	assert ion_webview_next(b) === -1 as int32;
	assert ion_webview_alloc("a", 1 as int32) >= 0;
}

test "the table holds 32 webviews" {
	reset();
	for (let i = 0; i < 32; i++) assert ion_webview_alloc(`w${i}`, 0 as int32) >= 0;
	assert ion_webview_alloc("one more", 0 as int32) === -1 as int32;
}

test "an IPC message names the webview that sent it" {
	reset();
	ion_queue_push_w(4 as int32, "ping", "x");
	ion_queue_push_w(-1 as int32, "tray.click", "");
	assert ion_queue_pop() === 1 as int32;
	assert ionMessageWebviewId() === 4 as int32;
	assert ion_queue_pop() === 1 as int32;
	assert ionMessageWebviewId() === -1 as int32;
}
