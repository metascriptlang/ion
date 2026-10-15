// Ion macOS - microphone access through AVCaptureDevice, the calls Electron makes in
// shell/browser/api/electron_api_system_preferences_mac.mm (GetMediaAccessStatus, AskForMediaAccess).
// The bundle's Info.plist needs NSMicrophoneUsageDescription or the prompt never appears.

#import "../../bridge.h"
#import <AVFoundation/AVFoundation.h>

static int stateOf(AVAuthorizationStatus status) {
	switch (status) {
		case AVAuthorizationStatusAuthorized: return ION_MIC_GRANTED;
		case AVAuthorizationStatusNotDetermined: return ION_MIC_UNDETERMINED | ION_MIC_CAN_ASK;
		case AVAuthorizationStatusDenied:
		case AVAuthorizationStatusRestricted: return ION_MIC_DENIED;
	}
	return ION_MIC_E_QUERY;
}

int ionMicAccess(void) {
	return stateOf([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio]);
}

int ionMicRequest(void) {
	if (stateOf([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio]) != (ION_MIC_UNDETERMINED | ION_MIC_CAN_ASK)) {
		return ionMicAccess();
	}
	dispatch_semaphore_t answered = dispatch_semaphore_create(0);
	[AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL granted) {
		dispatch_semaphore_signal(answered);
	}];
	dispatch_semaphore_wait(answered, DISPATCH_TIME_FOREVER);
	return ionMicAccess();
}

const char *ionMicErrorName(int code) {
	switch (code) {
		case ION_MIC_E_QUERY: return "AVCaptureDevice returned an unknown authorization status";
		default: return "unknown microphone error";
	}
}
