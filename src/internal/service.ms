// Mirror ION_SERVICE_* in bridge.h.
const ION_SERVICE_DONE: int32 = 1 as int32;
const ION_SERVICE_NO_WINDOW: int32 = 0 as int32;
const ION_SERVICE_UNSUPPORTED: int32 = -1 as int32;

export function serviceResult(what: string, code: int32): Result<void, string> {
	if (code === ION_SERVICE_DONE) return Result.ok(null);
	if (code === ION_SERVICE_NO_WINDOW) return Result.err(`${what}: the app has no active window`);
	if (code === ION_SERVICE_UNSUPPORTED) return Result.err(`${what}: not available on this platform`);
	return Result.err(`${what}: the OS refused the request`);
}
