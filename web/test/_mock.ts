// Mock window.__ion__ transport for bun:test. Must be imported BEFORE
// importing src/index.ts (which throws at module-load if window.__ion__
// is missing).

interface Posted {
	name: string;
	payload: string;
}

const _posted: Posted[] = [];
let _receiver: ((name: string, payload: string) => void) | null = null;

(globalThis as unknown as { window: unknown }).window = {
	__ion__: {
		post: (name: string, payload: string) => {
			_posted.push({ name, payload });
		},
		setReceiver: (fn: (name: string, payload: string) => void) => {
			_receiver = fn;
		},
	},
};

export const mock = {
	/** All envelopes posted via window.__ion__.post (FIFO order). */
	posted: _posted,
	/** Most recent posted envelope, or undefined if none. */
	last(): Posted | undefined {
		return _posted[_posted.length - 1];
	},
	/** Clear the posted log. */
	reset(): void {
		_posted.length = 0;
	},
	/** Simulate the native side dispatching a message back to JS. */
	simulate(name: string, payload: string): void {
		if (_receiver) _receiver(name, payload);
	},
};
