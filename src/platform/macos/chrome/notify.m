// Ion macOS — OS notifications via UNUserNotificationCenter.
//
// First call requests permission once; subsequent calls reuse the granted
// state. If the user denies (or hasn't responded yet), notify() is a no-op
// until they grant in System Settings.
//
// Click on a notification → "notification.click" IPC with payload = the id
// passed at notify time + main window brought to front.

#import "../state.h"
#import "../../bridge.h"
#import <UserNotifications/UserNotifications.h>
#import <Cocoa/Cocoa.h>

@interface IonNotifDelegate : NSObject <UNUserNotificationCenterDelegate>
@end

@implementation IonNotifDelegate
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions))h {
    // Show banner + sound even when our app is foreground.
    h(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionSound);
}
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
didReceiveNotificationResponse:(UNNotificationResponse *)response
         withCompletionHandler:(void (^)(void))h {
    NSString *identifier = response.notification.request.identifier;
    ionEnqueueMessage(@"notification.click", identifier);
    [NSApp activateIgnoringOtherApps:YES];
    if (s_nsWindow) [s_nsWindow makeKeyAndOrderFront:nil];
    h();
}
@end

static IonNotifDelegate *s_notifDelegate       = nil;
static BOOL              s_notifAuthRequested  = NO;

void ionNotify(const char *title, const char *body, const char *identifier) {
    if (title == NULL) title = "";
    if (body  == NULL) body  = "";
    if (identifier == NULL || identifier[0] == '\0') identifier = "ion-notif";

    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    if (s_notifDelegate == nil) {
        s_notifDelegate = [[IonNotifDelegate alloc] init];
        center.delegate = s_notifDelegate;
    }
    if (!s_notifAuthRequested) {
        s_notifAuthRequested = YES;
        [center requestAuthorizationWithOptions:
            (UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge)
                              completionHandler:^(BOOL granted, NSError *err) { (void)err; (void)granted; }];
    }

    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = [NSString stringWithUTF8String:title];
    content.body  = [NSString stringWithUTF8String:body];
    content.sound = [UNNotificationSound defaultSound];

    UNNotificationRequest *req =
        [UNNotificationRequest requestWithIdentifier:[NSString stringWithUTF8String:identifier]
                                              content:content
                                              trigger:nil];
    [center addNotificationRequest:req withCompletionHandler:^(NSError *err) { (void)err; }];
}
