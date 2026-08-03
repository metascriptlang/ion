// Typed error class for IPC failures. Lets callers distinguish failure modes
// via `instanceof IpcError` + `err.kind` instead of fragile string matching
// on Error.message.

export type IpcErrorKind =
	/** MS-side handler threw or returned an error envelope. */
	| "handler-error"
	/** call() exceeded its timeout window. */
	| "timeout"
	/** window.__ion__ wasn't injected — page wasn't loaded inside an ion webview. */
	| "transport-missing";

export class IpcError extends Error {
	readonly kind: IpcErrorKind;

	constructor(kind: IpcErrorKind, message: string) {
		super(message);
		this.name = "IpcError";
		this.kind = kind;
		// Preserve prototype chain when transpiled to ES5 targets that lose it.
		Object.setPrototypeOf(this, IpcError.prototype);
	}
}
