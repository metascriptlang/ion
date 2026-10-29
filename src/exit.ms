// Handlers for an app quit the user asked for (Cmd+Q, the Quit item, a quit Apple Event on
// macOS), as Tauri's RunEvent::ExitRequested. SIGINT, SIGTERM and the last window closing end
// the loop without asking.

export type ExitRequestedHandler = () => void;

const _exitHandlers: ExitRequestedHandler[] = [];
let _exitDispatching = false;
let _exitPrevented = false;

export function onExitRequested(fn: ExitRequestedHandler): void { _exitHandlers.push(fn); }

// Inside an onExitRequested handler: the app keeps running (Tauri's ExitRequestApi::prevent_exit).
export function preventExit(): void {
	if (!_exitDispatching) {
		console.error("[ion] preventExit: called outside an exit-requested handler, so the app was not held");
		return;
	}
	_exitPrevented = true;
}

// Returns whether the loop should end.
export function dispatchExitRequested(): boolean {
	_exitDispatching = true;
	_exitPrevented = false;
	for (const h of _exitHandlers) h();
	_exitDispatching = false;
	return !_exitPrevented;
}
