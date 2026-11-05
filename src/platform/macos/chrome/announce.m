// Ion macOS — screen reader announcement on the key window.

#import <Cocoa/Cocoa.h>
#include "../../bridge.h"

int ionAnnounce(const char *text) {
    NSWindow *window = NSApp.keyWindow ?: NSApp.mainWindow;
    if (window == nil) return ION_SERVICE_NO_WINDOW;
    NSString *s = [NSString stringWithUTF8String:text];
    if (s == nil) return ION_SERVICE_REFUSED;
    NSAccessibilityPostNotificationWithUserInfo(window, NSAccessibilityAnnouncementRequestedNotification, @{
        NSAccessibilityAnnouncementKey: s,
        NSAccessibilityPriorityKey: @(NSAccessibilityPriorityHigh),
    });
    return ION_SERVICE_DONE;
}
