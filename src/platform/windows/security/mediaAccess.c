// Ion Windows - microphone and camera access state.
//
// Reads Windows.Devices.Enumeration.DeviceAccessInformation for AudioCapture or VideoCapture, the
// call behind Electron's systemPreferences.getMediaAccessStatus("microphone" / "camera")
// (shell/browser/api/electron_api_system_preferences_win.cc). Measured to answer for an
// unpackaged exe. Desktop apps get no OS prompt, so ionMediaRequest returns the same state
// and CAN_ASK is never set.

#include "../../bridge.h"

#include <windows.h>

// zig's bundled MinGW has no WinRT headers: only the three vtable slots used are named.
typedef struct {
	void *queryInterface;
	void *addRef;
	ULONG (STDMETHODCALLTYPE *release)(void *self);
	void *inspectable[3];
} InspectableHead;

typedef struct DeviceAccessInformation DeviceAccessInformation;
typedef struct {
	InspectableHead head;
	void *addAccessChanged;
	void *removeAccessChanged;
	HRESULT (STDMETHODCALLTYPE *getCurrentStatus)(DeviceAccessInformation *self, int *status);
} InformationVtbl;
struct DeviceAccessInformation { const InformationVtbl *vtbl; };

typedef struct DeviceAccessStatics DeviceAccessStatics;
typedef struct {
	InspectableHead head;
	void *createFromId;
	void *createFromDeviceClassId;
	HRESULT (STDMETHODCALLTYPE *createFromDeviceClass)(DeviceAccessStatics *self, int deviceClass, DeviceAccessInformation **out);
} StaticsVtbl;
struct DeviceAccessStatics { const StaticsVtbl *vtbl; };

typedef HRESULT (WINAPI *RefFn)(PCWSTR, UINT32, void *, void **);
typedef HRESULT (WINAPI *FactoryFn)(void *, const GUID *, void **);
typedef HRESULT (WINAPI *InitFn)(int);
typedef void (WINAPI *UninitFn)(void);

#define DEVICE_CLASS_AUDIO_CAPTURE 1
#define DEVICE_CLASS_VIDEO_CAPTURE 4
#define STATUS_ALLOWED 1
#define STATUS_UNSPECIFIED 0

static const GUID IID_DeviceAccessInformationStatics =
	{ 0x574bd3d3, 0x5f30, 0x45cd, { 0x8a, 0x94, 0x72, 0x4f, 0xe5, 0x97, 0x30, 0x84 } };

static int currentStatus(int deviceClass) {
	HMODULE combase = LoadLibraryW(L"combase.dll");
	if (!combase) { return ION_MEDIA_E_UNAVAILABLE; }
	RefFn ref = (RefFn)GetProcAddress(combase, "WindowsCreateStringReference");
	FactoryFn factory = (FactoryFn)GetProcAddress(combase, "RoGetActivationFactory");
	InitFn init = (InitFn)GetProcAddress(combase, "RoInitialize");
	UninitFn uninit = (UninitFn)GetProcAddress(combase, "RoUninitialize");
	if (!ref || !factory || !init || !uninit) { return ION_MEDIA_E_UNAVAILABLE; }

	// S_OK and S_FALSE both need a RoUninitialize; RPC_E_CHANGED_MODE means the thread is already COM-initialised.
	HRESULT initHr = init(1);
	int mustUninit = initHr == S_OK || initHr == S_FALSE;

	static const WCHAR className[] = L"Windows.Devices.Enumeration.DeviceAccessInformation";
	char header[24];
	void *name = NULL;
	int result = ION_MEDIA_E_QUERY;
	DeviceAccessStatics *statics = NULL;
	if (SUCCEEDED(ref(className, (UINT32)(sizeof(className) / sizeof(WCHAR) - 1), header, &name))
		&& SUCCEEDED(factory(name, &IID_DeviceAccessInformationStatics, (void **)&statics))) {
		DeviceAccessInformation *info = NULL;
		int status = -1;
		if (SUCCEEDED(statics->vtbl->createFromDeviceClass(statics, deviceClass, &info))
			&& SUCCEEDED(info->vtbl->getCurrentStatus(info, &status))) {
			result = status;
		}
		if (info) { info->vtbl->head.release(info); }
	}
	if (statics) { statics->vtbl->head.release(statics); }
	if (mustUninit) { uninit(); }
	return result;
}

int ionMediaAccess(int kind) {
	int deviceClass = kind == ION_MEDIA_MICROPHONE ? DEVICE_CLASS_AUDIO_CAPTURE
		: kind == ION_MEDIA_CAMERA ? DEVICE_CLASS_VIDEO_CAPTURE : -1;
	if (deviceClass < 0) { return ION_MEDIA_E_KIND; }
	int status = currentStatus(deviceClass);
	if (status < 0) { return status; }
	if (status == STATUS_ALLOWED) { return ION_MEDIA_GRANTED; }
	if (status == STATUS_UNSPECIFIED) { return ION_MEDIA_UNDETERMINED; }
	return ION_MEDIA_DENIED;
}

int ionMediaRequest(int kind) { return ionMediaAccess(kind); }

const char *ionMediaErrorName(int code) {
	switch (code) {
		case ION_MEDIA_E_UNAVAILABLE: return "the WinRT runtime is not available";
		case ION_MEDIA_E_QUERY: return "DeviceAccessInformation did not answer";
		case ION_MEDIA_E_KIND: return "unknown media device kind";
		default: return "unknown media access error";
	}
}
