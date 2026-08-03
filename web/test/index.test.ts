// Tests for @metascriptlang/ion. Mock window.__ion__ transport via _mock,
// then exercise the public API.

import { mock } from "./_mock";  // MUST be first — sets window.__ion__
import { test, expect, beforeEach } from "bun:test";
import { call, invoke, on, off, IpcError } from "../src/index";

beforeEach(() => {
	mock.reset();
});

// ---- invoke -----------------------------------------------------------------

test("invoke posts on the given channel with payload", () => {
	invoke("ready", "ok");
	const last = mock.last();
	expect(last).toBeDefined();
	expect(last!.name).toBe("ready");
	expect(last!.payload).toBe("ok");
});

test("invoke defaults payload to empty string", () => {
	invoke("ping");
	expect(mock.last()!.payload).toBe("");
});

// ---- on / off ---------------------------------------------------------------

test("on receives MS-initiated message of matching name", () => {
	let received = "";
	on("greeting", (p) => { received = p; });
	mock.simulate("greeting", "hello");
	expect(received).toBe("hello");
});

test("off removes the handler", () => {
	let count = 0;
	on("event", () => { count = count + 1; });
	mock.simulate("event", "");
	off("event");
	mock.simulate("event", "");
	expect(count).toBe(1);
});

test("on with same name replaces previous handler", () => {
	let first = false, second = false;
	on("once", () => { first = true; });
	on("once", () => { second = true; });
	mock.simulate("once", "");
	expect(first).toBe(false);
	expect(second).toBe(true);
});

test("MS-initiated message with no handler is silently dropped", () => {
	// No registration; simulating shouldn't throw.
	expect(() => mock.simulate("nobody-listens", "")).not.toThrow();
});

// ---- call (success path) ---------------------------------------------------

test("call posts envelope on __call channel with id + name + args", () => {
	call("addNumbers", { a: 1, b: 2 });
	const last = mock.last()!;
	expect(last.name).toBe("__call");
	const env = JSON.parse(last.payload);
	expect(env.name).toBe("addNumbers");
	expect(env.args).toEqual({ a: 1, b: 2 });
	expect(typeof env.id).toBe("string");
});

test("call resolves with value when MS responds with success envelope", async () => {
	const promise = call<number>("op", null);
	const id = JSON.parse(mock.last()!.payload).id;
	mock.simulate("__response", JSON.stringify({ id, value: 42 }));
	expect(await promise).toBe(42);
});

test("call rejects with IpcError(handler-error) on error envelope", async () => {
	const promise = call("failing", null);
	const id = JSON.parse(mock.last()!.payload).id;
	mock.simulate("__response", JSON.stringify({ id, error: "MS handler threw" }));
	try {
		await promise;
		throw new Error("expected reject");
	} catch (e) {
		expect(e).toBeInstanceOf(IpcError);
		expect((e as IpcError).kind).toBe("handler-error");
		expect((e as IpcError).message).toBe("MS handler threw");
	}
});

test("concurrent calls get distinct ids", () => {
	call("a", {});
	call("b", {});
	call("c", {});
	const ids = mock.posted.slice(-3).map((p) => JSON.parse(p.payload).id);
	expect(new Set(ids).size).toBe(3);
});

test("response with unknown id is silently dropped", () => {
	expect(() => mock.simulate("__response", JSON.stringify({ id: "does-not-exist", value: 1 }))).not.toThrow();
});

test("malformed JSON __response is silently dropped", () => {
	expect(() => mock.simulate("__response", "not-json{")).not.toThrow();
});

// ---- call (timeout) --------------------------------------------------------

test("call rejects with IpcError(timeout) when no response within timeout", async () => {
	const promise = call("slow", null, { timeout: 30 });
	try {
		await promise;
		throw new Error("expected reject");
	} catch (e) {
		expect(e).toBeInstanceOf(IpcError);
		expect((e as IpcError).kind).toBe("timeout");
		expect((e as IpcError).message).toContain('"slow"');
		expect((e as IpcError).message).toContain("30ms");
	}
});

test("response after timeout is silently dropped (no double-resolve)", async () => {
	const promise = call("eventual", null, { timeout: 20 });
	const id = JSON.parse(mock.last()!.payload).id;
	try { await promise; } catch {}
	// Late response — pending entry is gone, simulate should no-op.
	expect(() => mock.simulate("__response", JSON.stringify({ id, value: 99 }))).not.toThrow();
});

test("response before timeout cancels the timer", async () => {
	const promise = call<string>("fast", null, { timeout: 1000 });
	const id = JSON.parse(mock.last()!.payload).id;
	mock.simulate("__response", JSON.stringify({ id, value: "ok" }));
	expect(await promise).toBe("ok");
	// If timer wasn't cleared, the pending entry would still exist; nothing
	// observable from outside, but at minimum we got the value cleanly.
});

test("no timeout option = no auto-reject", async () => {
	const promise = call("forever", null);
	let resolved = false;
	promise.then(() => { resolved = true; }).catch(() => { resolved = true; });
	await new Promise((r) => setTimeout(r, 50));
	expect(resolved).toBe(false);
	// Clean up so test doesn't leave a permanently-pending Promise.
	const id = JSON.parse(mock.last()!.payload).id;
	mock.simulate("__response", JSON.stringify({ id, value: null }));
	await promise;
});

// ---- IpcError --------------------------------------------------------------

test("IpcError has kind property and instanceof works", () => {
	const e = new IpcError("timeout", "test");
	expect(e).toBeInstanceOf(Error);
	expect(e).toBeInstanceOf(IpcError);
	expect(e.kind).toBe("timeout");
	expect(e.name).toBe("IpcError");
});
