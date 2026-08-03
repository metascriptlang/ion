// Windows OTA install — STUB. Same role as the Linux stub: lets update.ms
// link on a Windows cross-compile target while apply()'s platform guard
// refuses to invoke at runtime.
//
// Real Windows install design (deferred): NSIS installer .exe spawned
// elevated via ShellExecuteEx with the "runas" verb (triggers UAC). Or, for
// future SquirrelWindows-style in-place updates, rename .exe-old + drop new
// .exe alongside via MOVEFILE_REPLACE_EXISTING.

#include <stdint.h>
#include "../../bridge.h"
#include "runtime/core/string.h"

#define ION_UPDATE_NOT_IMPL (-99)

msString ionUpdateMountDmg(const char *dmgPath) {
	(void)dmgPath;
	return MS_EMPTY_STRING;
}

msString ionUpdateFindAppInVolume(const char *mountPoint) {
	(void)mountPoint;
	return MS_EMPTY_STRING;
}

int ionUpdateReplaceApp(const char *srcAppPath, const char *destAppPath) {
	(void)srcAppPath; (void)destAppPath;
	return ION_UPDATE_NOT_IMPL;
}

int ionUpdateUnmountDmg(const char *mountPoint) {
	(void)mountPoint;
	return ION_UPDATE_NOT_IMPL;
}

int ionUpdateRelaunchAndExit(const char *destAppPath) {
	(void)destAppPath;
	return ION_UPDATE_NOT_IMPL;
}
