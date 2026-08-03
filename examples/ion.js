// @metascriptlang/ion — typed JS↔MS IPC for ion webview apps.
//
// Usage (inside an ion webview):
//
//   import { call, invoke, on } from "@metascriptlang/ion";
//
//   const sum = await call<number>("addNumbers", { a: 3, b: 5 });
//
//   on("notification.click", (id) => console.log("user tapped", id));
//
//   invoke("ready", "");
//
// Wire protocol details:
//   - `call(name, args)` posts envelope `{id, name, args}` on channel "__call".
//     MS handler returns a JSON value; we resolve the Promise with the parsed
//     result. Errors thrown by the MS handler reject the Promise.
//   - `invoke(name, payload)` is fire-and-forget. Use when you don't need a reply.
//   - `on(name, handler)` registers a JS handler for MS-initiated messages.
//
// Transport: this module talks to native via `window.__ion__` — a closure-
// scoped object injected by ion's WKWebView/WebView2 bootstrap that carries
// the per-launch invoke_key. iframes and content outside our injection path
// don't get `window.__ion__`, so they cannot reach the IPC.
import { CHANNEL_CALL, CHANNEL_RESPONSE, FIELD_ID, FIELD_VALUE, FIELD_ERROR } from "./protocol";
if (typeof window === "undefined" || !window.__ion__) {
    throw new Error("@metascript/ion: native transport (window.__ion__) not available. " +
        "This package only runs inside an ion webview.");
}
const _transport = window.__ion__;
const _handlers = new Map();
const _pending = new Map();
let _nextId = 0;
_transport.setReceiver((name, payload) => {
    if (name === CHANNEL_RESPONSE) {
        try {
            const msg = JSON.parse(payload);
            const id = msg[FIELD_ID];
            if (id === undefined)
                return;
            const p = _pending.get(id);
            if (!p)
                return;
            _pending.delete(id);
            const err = msg[FIELD_ERROR];
            if (err)
                p.reject(new Error(err));
            else
                p.resolve(msg[FIELD_VALUE]);
        }
        catch {
            // Malformed response — drop silently. Caller's Promise stays pending,
            // which is correct: we have no way to know which Promise it was for.
        }
        return;
    }
    const h = _handlers.get(name);
    if (h)
        h(payload);
});
// ---- Public API ------------------------------------------------------------
/**
 * Fire-and-forget message to MS native. MS-side `listen()` handlers receive
 * `(name, payload)`. Use `call()` instead when you need a reply.
 */
export function invoke(name, payload = "") {
    _transport.post(name, payload);
}
/**
 * Register a handler for MS→JS messages of the given name. MS code calls
 * `invoke(name, payload)` from the native side; the matching handler here
 * receives the payload string.
 *
 * Only one handler per name (replaces any previous registration).
 */
export function on(name, handler) {
    _handlers.set(name, handler);
}
/**
 * Remove the handler for `name`. No-op if none registered.
 */
export function off(name) {
    _handlers.delete(name);
}
/**
 * Tauri-style Promise call. MS-side `command(name, fn)` handlers receive the
 * args as a JSON string and return a JSON string; this resolves to the parsed
 * value. The handler can throw — the rejection bubbles into a rejected Promise.
 *
 * Type parameter `T` lets you tag the expected return type for IDE autocomplete.
 * Runtime is dynamic — callers should validate critical responses themselves.
 */
export function call(name, args = null) {
    return new Promise((resolve, reject) => {
        const id = String(++_nextId);
        _pending.set(id, {
            resolve: (v) => resolve(v),
            reject,
        });
        _transport.post(CHANNEL_CALL, JSON.stringify({ [FIELD_ID]: id, name, args }));
    });
}
//# sourceMappingURL=index.js.map