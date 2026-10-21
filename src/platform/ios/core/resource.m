#import <Foundation/Foundation.h>
#include "../../bridge.h"

msString ionResourcePath(void) {
    const char *path = NSBundle.mainBundle.resourcePath.UTF8String;
    return path ? msStringFromCStr(path) : MS_EMPTY_STRING;
}
