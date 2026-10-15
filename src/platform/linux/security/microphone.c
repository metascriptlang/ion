// Ion Linux - microphone access. Outside a sandbox the OS has no microphone gate, so granted is the
// true answer. Inside Flatpak the desktop portal decides and no portal call is built yet.

#include "../../bridge.h"

#include <unistd.h>

int ionMicAccess(void) {
	if (access("/.flatpak-info", F_OK) == 0) { return ION_MIC_E_SANDBOX; }
	return ION_MIC_GRANTED | ION_MIC_CAN_ASK;
}

int ionMicRequest(void) { return ionMicAccess(); }

const char *ionMicErrorName(int code) {
	switch (code) {
		case ION_MIC_E_SANDBOX: return "running inside Flatpak: the microphone portal is not built";
		default: return "unknown microphone error";
	}
}
