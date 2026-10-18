// Ion Linux - microphone and camera access. Outside a sandbox the OS has no gate for either, so
// granted is the true answer. Inside Flatpak the desktop portal decides and no portal call is
// built yet.

#include "../../bridge.h"

#include <unistd.h>

int ionMediaAccess(int kind) {
	if (kind != ION_MEDIA_MICROPHONE && kind != ION_MEDIA_CAMERA) { return ION_MEDIA_E_KIND; }
	if (access("/.flatpak-info", F_OK) == 0) { return ION_MEDIA_E_SANDBOX; }
	return ION_MEDIA_GRANTED | ION_MEDIA_CAN_ASK;
}

int ionMediaRequest(int kind) { return ionMediaAccess(kind); }

const char *ionMediaErrorName(int code) {
	switch (code) {
		case ION_MEDIA_E_SANDBOX: return "running inside Flatpak: the device portals are not built";
		case ION_MEDIA_E_KIND: return "unknown media device kind";
		default: return "unknown media access error";
	}
}
