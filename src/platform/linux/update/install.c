// Linux OTA install — STUB. The Linux update bridge isn't wired yet; this
// file exists only so std/ion update.ms can link on a Linux target. apply()
// in update.ms guards by cfg.platform.startsWith("darwin") and will refuse
// to invoke these stubs at runtime — so calls into them indicate a caller
// bug (forgetting the platform guard).
//
// Real Linux install design (deferred): AppImage atomic replace via rename(2)
// over the running AppImage path. polkit pkexec for /Applications-equivalent
// paths (/usr/local/bin) or skip elevation entirely for ~/Applications.

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
