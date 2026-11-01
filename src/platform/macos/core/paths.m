// Ion macOS — the app's identifier: its bundle id, or the process name when it runs unbundled.

#import <Foundation/Foundation.h>
#include "../../bridge.h"

msString ionAppIdentifier(void) {
    NSString *id = NSBundle.mainBundle.bundleIdentifier ?: NSProcessInfo.processInfo.processName;
    const char *utf8 = id.UTF8String;
    return utf8 ? msStringFromCStr(utf8) : MS_EMPTY_STRING;
}
