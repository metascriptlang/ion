// Ion Android - app resources live inside the APK and are read through the AAssetManager the
// generated MainActivity hands to the generated ionAssets.c before MsMain runs.

#include <android/asset_manager.h>
#include <string.h>
#include "../../bridge.h"

extern AAssetManager *ionAndroidAssets;

static int s_status;

msString ionResourcePath(void) {
    return msStringFromCStr("/android_asset");
}

msString ionReadAsset(const char *path) {
    if (ionAndroidAssets == NULL) {
        s_status = -1;
        return MS_EMPTY_STRING;
    }
    AAsset *asset = AAssetManager_open(ionAndroidAssets, path, AASSET_MODE_BUFFER);
    if (asset == NULL) {
        s_status = 0;
        return MS_EMPTY_STRING;
    }
    off64_t length = AAsset_getLength64(asset);
    const void *bytes = AAsset_getBuffer(asset);
    msString result = bytes ? msStringNew((const char *)bytes, (int64_t)length) : MS_EMPTY_STRING;
    s_status = bytes ? 1 : 0;
    AAsset_close(asset);
    return result;
}

int ionAssetStatus(void) {
    return s_status;
}
