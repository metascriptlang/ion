// Tests for src/platform/common/queue.{c,h}.
// Pure C — no platform deps.
//
// CAVEAT: queue is process-global state. Tests run in the same binary so
// pushes from earlier tests persist. Each test drains the queue first.

@compile("../../src/platform/common/queue.c");
@include("../../src/platform/common/queue.h");

// queue.c returns const char* (C-internal contract — see queue.h docs).
// MS-side tests wrap with msStringFromCStr at the call site, matching the
// canonical FFI conversion runtime helper.
extern function msStringFromCStr(cstr: cstring): string;

extern function ion_queue_push(name: cstring, payload: cstring): int32;
extern function ion_queue_pop(): int32;
extern function ion_queue_last_name(): cstring;
extern function ion_queue_last_payload(): cstring;

function drain(): void {
	while (ion_queue_pop() === 1 as int32) {}
}

test "pop on empty queue returns 0" {
	drain();
	assert ion_queue_pop() === 0 as int32;
}

test "push returns 0 on success" {
	drain();
	assert ion_queue_push("ok", "value") === 0 as int32;
}

test "push then pop returns 1 with correct name + payload" {
	drain();
	ion_queue_push("hello", "world");
	assert ion_queue_pop() === 1 as int32;
	assert msStringFromCStr(ion_queue_last_name()) === "hello";
	assert msStringFromCStr(ion_queue_last_payload()) === "world";
}

test "FIFO order — first pushed is first popped" {
	drain();
	ion_queue_push("first", "1");
	ion_queue_push("second", "2");
	ion_queue_push("third", "3");
	assert ion_queue_pop() === 1 as int32;
	assert msStringFromCStr(ion_queue_last_name()) === "first";
	assert ion_queue_pop() === 1 as int32;
	assert msStringFromCStr(ion_queue_last_name()) === "second";
	assert ion_queue_pop() === 1 as int32;
	assert msStringFromCStr(ion_queue_last_name()) === "third";
	assert ion_queue_pop() === 0 as int32;
}

test "interleaved push/pop preserves order" {
	drain();
	ion_queue_push("a", "1");
	ion_queue_push("b", "2");
	assert ion_queue_pop() === 1 as int32;
	assert msStringFromCStr(ion_queue_last_name()) === "a";
	ion_queue_push("c", "3");
	assert ion_queue_pop() === 1 as int32;
	assert msStringFromCStr(ion_queue_last_name()) === "b";
	assert ion_queue_pop() === 1 as int32;
	assert msStringFromCStr(ion_queue_last_name()) === "c";
	assert ion_queue_pop() === 0 as int32;
}

test "empty payload accepted" {
	drain();
	ion_queue_push("name-only", "");
	assert ion_queue_pop() === 1 as int32;
	assert msStringFromCStr(ion_queue_last_name()) === "name-only";
	assert msStringFromCStr(ion_queue_last_payload()) === "";
}

test "long payload preserved" {
	drain();
	const long = "abcdefghijklmnopqrstuvwxyz0123456789".repeat(10 as int64);
	ion_queue_push("big", long);
	assert ion_queue_pop() === 1 as int32;
	assert msStringFromCStr(ion_queue_last_payload()) === long;
}

test "many push then drain — count matches" {
	drain();
	for (let i = 0; i < 50; i = i + 1) {
		ion_queue_push("msg", `${i}`);
	}
	let popped = 0;
	while (ion_queue_pop() === 1 as int32) popped = popped + 1;
	assert popped === 50;
}

test "last_name persists until next push or pop" {
	drain();
	ion_queue_push("persistent", "p");
	assert ion_queue_pop() === 1 as int32;
	const first = msStringFromCStr(ion_queue_last_name());
	const second = msStringFromCStr(ion_queue_last_name());  // re-read without popping
	assert first === second;
	assert first === "persistent";
}
