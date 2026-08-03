// @metascriptlang/ion — typed JS↔MS IPC for ion webview apps.
//
// Usage (inside an ion webview):
//
//   import { call, invoke, on, IpcError } from "@metascriptlang/ion";
//
//   const sum = await call<number>("addNumbers", { a: 3, b: 5 });
//
//   on("notification.click", (id) => console.log("user tapped", id));
//
//   invoke("ready", "");
//
// Wire protocol: see ./protocol.ts (mirrors src/platform/common/protocol.h).
//
// Transport: this module talks to native via `window.__ion__` — a closure-
// scoped object injected by ion's WKWebView/WebView2 bootstrap that carries
// the per-launch invoke_key. iframes and content outside our injection path
// don't get `window.__ion__`, so they cannot reach the IPC.

import {
	CHANNEL_CALL, CHANNEL_RESPONSE, CHANNEL_EMIT,
	FIELD_ID, FIELD_VALUE, FIELD_ERROR,
	FIELD_TARGET, FIELD_EVENT, FIELD_PAYLOAD,
} from "./protocol";
import { IpcError } from "./errors";

export { IpcError };
export type { IpcErrorKind } from "./errors";

declare global {
	interface Window {
		__ion__?: {
			/** Window label injected by the native bootstrap. "" in legacy single-window builds. */
			label: string;
			post: (name: string, payload: string) => void;
			setReceiver: (fn: (name: string, payload: string) => void) => void;
		};
	}
}

if (typeof window === "undefined" || !window.__ion__) {
	throw new IpcError(
		"transport-missing",
		"@metascriptlang/ion: native transport (window.__ion__) not available. " +
		"This package only runs inside an ion webview."
	);
}

const _transport = window.__ion__;
const _handlers = new Map<string, (payload: string) => void>();

interface PendingEntry {
	resolve: (v: unknown) => void;
	reject: (e: Error) => void;
	timer?: ReturnType<typeof setTimeout>;
}
const _pending = new Map<string, PendingEntry>();
let _nextId = 0;

_transport.setReceiver((name, payload) => {
	if (name === CHANNEL_RESPONSE) {
		try {
			const msg = JSON.parse(payload) as Record<string, unknown>;
			const id = msg[FIELD_ID] as string | undefined;
			if (id === undefined) return;
			const p = _pending.get(id);
			if (!p) return;
			_pending.delete(id);
			if (p.timer !== undefined) clearTimeout(p.timer);
			const err = msg[FIELD_ERROR] as string | undefined;
			if (err) p.reject(new IpcError("handler-error", err));
			else p.resolve(msg[FIELD_VALUE]);
		} catch {
			// Malformed response — drop silently. Caller's Promise stays pending,
			// but their timeout (if set) will eventually clean up.
		}
		return;
	}
	const h = _handlers.get(name);
	if (h) h(payload);
});

// ---- Public API ------------------------------------------------------------

/**
 * Fire-and-forget message to MS native.
 *
 * MS-side `listen()` handlers receive `(name, payload)`. Use `call()` instead
 * when you need a reply.
 *
 * @param name - channel name MS-side listens on
 * @param payload - opaque string passed through; serialize JSON yourself if needed
 *
 * @example
 *   invoke("ready", "");
 *   invoke("user-action", JSON.stringify({ kind: "click", id: 42 }));
 */
export function invoke(name: string, payload: string = ""): void {
	_transport.post(name, payload);
}

/**
 * Register a handler for MS-initiated messages of the given name.
 *
 * MS code calls `invoke(name, payload)` from the native side; the matching
 * handler here receives the payload string. Only one handler per name —
 * subsequent calls replace the previous registration.
 *
 * @param name - channel name MS-side will dispatch on
 * @param handler - called with the payload string each time MS posts to this name
 *
 * @example
 *   on("notification.click", (id) => console.log("user tapped", id));
 *   on("deeplink", (url) => router.navigate(url));
 */
export function on(name: string, handler: (payload: string) => void): void {
	_handlers.set(name, handler);
}

/**
 * Remove the handler for `name`. No-op if none registered.
 */
export function off(name: string): void {
	_handlers.delete(name);
}

/**
 * Returns this webview's window label (e.g. "main", "quick-panel"). The
 * label is injected by the native bootstrap at document-start and is
 * frozen for the lifetime of the page.
 *
 * @returns the label, or `""` in legacy single-window builds where the
 * native side didn't tag a label.
 *
 * @example
 *   if (getCurrentLabel() === "quick-panel") { ... }
 */
export function getCurrentLabel(): string {
	return _transport.label || "";
}

/**
 * Broadcast an event to every ion window in this process (including this
 * one). Listeners registered via `on(event, handler)` on any window's
 * `@metascriptlang/ion` import will fire.
 *
 * @param event - event name (alphanumeric + `-` / `/` / `:` / `_`)
 * @param payload - opaque string passed through unchanged
 *
 * @example
 *   emit("theme-changed", "dark");
 */
export function emit(event: string, payload: string = ""): void {
	emitTo("", event, payload);
}

/**
 * Send an event to a specific ion window by label. Pass `""` as `target`
 * to broadcast (equivalent to `emit`).
 *
 * Routing: this webview cannot reach another webview directly. The event
 * goes JS → native (via the `__emit` reserved channel) → MS-side router →
 * `ionEvalJSWindow` into the target webview's `_dispatch`, which fires
 * the matching `on(event, handler)` callback there.
 *
 * @param target - label of the receiving window, or `""` to broadcast
 * @param event - event name (alphanumeric + `-` / `/` / `:` / `_`)
 * @param payload - opaque string passed through unchanged
 *
 * @example
 *   // Panel tells main window the user picked an item
 *   emitTo("main", "item-picked", JSON.stringify({ id: 42 }));
 */
export function emitTo(target: string, event: string, payload: string = ""): void {
	_transport.post(CHANNEL_EMIT, JSON.stringify({
		[FIELD_TARGET]:  target,
		[FIELD_EVENT]:   event,
		[FIELD_PAYLOAD]: payload,
	}));
}

/**
 * Optional config for `call()`.
 */
export interface CallOptions {
	/**
	 * Reject the Promise with `IpcError("timeout", ...)` after this many ms
	 * if the MS handler hasn't responded. Cleans up the pending entry so it
	 * doesn't leak. Omit (or set to 0) for no timeout — Promise stays
	 * pending forever if the handler never responds.
	 */
	timeout?: number;
}

/**
 * Tauri-style Promise call to a MS-side `command(name, fn)` handler.
 *
 * MS handler receives the args as a JSON string, returns a JSON string. This
 * resolves to the parsed value. If the handler throws or returns an error
 * envelope, the Promise rejects with `IpcError("handler-error", message)`.
 *
 * @param name - command name registered MS-side via `command()`
 * @param args - JSON-serializable arguments object (or null)
 * @param opts - optional timeout
 * @returns Promise resolving to the handler's return value (typed as `T`)
 * @throws {IpcError} kind="handler-error" if MS handler returned an error envelope
 * @throws {IpcError} kind="timeout" if `opts.timeout` elapsed without a response
 *
 * @example
 *   // Basic typed call
 *   const sum = await call<number>("addNumbers", { a: 3, b: 5 });
 *
 *   // With timeout — rejects after 5 seconds
 *   const result = await call<string>("slowOp", null, { timeout: 5000 });
 *
 *   // Discriminate failure modes
 *   try {
 *     await call("risky", {}, { timeout: 1000 });
 *   } catch (e) {
 *     if (e instanceof IpcError && e.kind === "timeout") retry();
 *     else throw e;
 *   }
 */
export function call<T = unknown>(name: string, args: unknown = null, opts: CallOptions = {}): Promise<T> {
	return new Promise<T>((resolve, reject) => {
		const id = String(++_nextId);
		const entry: PendingEntry = {
			resolve: (v) => resolve(v as T),
			reject,
		};
		if (opts.timeout && opts.timeout > 0) {
			entry.timer = setTimeout(() => {
				if (_pending.delete(id)) {
					reject(new IpcError("timeout", `call("${name}") timed out after ${opts.timeout}ms`));
				}
			}, opts.timeout);
		}
		_pending.set(id, entry);
		_transport.post(CHANNEL_CALL, JSON.stringify({ [FIELD_ID]: id, name, args }));
	});
}
