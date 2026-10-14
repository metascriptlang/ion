// Handlers for ionWakeLoop: the loop thread runs them after any thread calls it.

export type WakeHandler = () => void;

const _wakeHandlers: WakeHandler[] = [];

// Runs `fn` on the loop thread each time ionWakeLoop is called, from any
// thread. Wakes that arrive before the loop runs them coalesce into one call.
export function onWake(fn: WakeHandler): void { _wakeHandlers.push(fn); }

export function dispatchWake(): void {
	for (const h of _wakeHandlers) h();
}
