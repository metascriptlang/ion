// Ion macOS - microphone and camera access through AVCaptureDevice, the calls Electron makes in
// shell/browser/api/electron_api_system_preferences_mac.mm (GetMediaAccessStatus, AskForMediaAccess).
// The bundle's Info.plist needs NSMicrophoneUsageDescription / NSCameraUsageDescription or the
// prompt never appears.

#import "../../bridge.h"
#import <AVFoundation/AVFoundation.h>

static AVMediaType mediaType(int kind) {
	switch (kind) {
		case ION_MEDIA_MICROPHONE: return AVMediaTypeAudio;
		case ION_MEDIA_CAMERA: return AVMediaTypeVideo;
	}
	return nil;
}

static int stateOf(AVAuthorizationStatus status) {
	switch (status) {
		case AVAuthorizationStatusAuthorized: return ION_MEDIA_GRANTED;
		case AVAuthorizationStatusNotDetermined: return ION_MEDIA_UNDETERMINED | ION_MEDIA_CAN_ASK;
		case AVAuthorizationStatusDenied:
		case AVAuthorizationStatusRestricted: return ION_MEDIA_DENIED;
	}
	return ION_MEDIA_E_QUERY;
}

int ionMediaAccess(int kind) {
	AVMediaType type = mediaType(kind);
	if (type == nil) { return ION_MEDIA_E_KIND; }
	return stateOf([AVCaptureDevice authorizationStatusForMediaType:type]);
}

int ionMediaRequest(int kind) {
	if (ionMediaAccess(kind) != (ION_MEDIA_UNDETERMINED | ION_MEDIA_CAN_ASK)) {
		return ionMediaAccess(kind);
	}
	dispatch_semaphore_t answered = dispatch_semaphore_create(0);
	[AVCaptureDevice requestAccessForMediaType:mediaType(kind) completionHandler:^(BOOL granted) {
		dispatch_semaphore_signal(answered);
	}];
	dispatch_semaphore_wait(answered, DISPATCH_TIME_FOREVER);
	return ionMediaAccess(kind);
}

const char *ionMediaErrorName(int code) {
	switch (code) {
		case ION_MEDIA_E_QUERY: return "AVCaptureDevice returned an unknown authorization status";
		case ION_MEDIA_E_KIND: return "unknown media device kind";
		default: return "unknown media access error";
	}
}
