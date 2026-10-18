#import <Cocoa/Cocoa.h>
#import <UserNotifications/UserNotifications.h>
#include <stdatomic.h>
#include "chromeMacos.h"

static NSButton *findButton(NSView *v, NSString *title) {
    if ([v isKindOfClass:[NSButton class]] && [((NSButton *)v).title isEqualToString:title]) return (NSButton *)v;
    for (NSView *sub in v.subviews) {
        NSButton *b = findButton(sub, title);
        if (b != nil) return b;
    }
    return nil;
}

static NSButton *trayButton(const char *title) {
    NSString *want = [NSString stringWithUTF8String:title];
    for (NSWindow *w in NSApp.windows) {
        NSButton *b = findButton(w.contentView, want);
        if (b != nil) return b;
    }
    return nil;
}

int chromeTrayVisible(const char *title) {
    NSButton *b = trayButton(title);
    if (b == nil || !b.window.isVisible) return 0;
    NSRect f = b.window.frame;
    for (NSScreen *s in NSScreen.screens) {
        if (NSMaxY(f) >= NSMaxY(s.frame) - 1 && NSIntersectsRect(f, s.frame)) return 1;
    }
    return 0;
}

int chromeTrayClick(const char *title) {
    NSButton *b = trayButton(title);
    if (b == nil) return 0;
    [b performClick:nil];
    return 1;
}

int chromeAppActive(void) { return NSApp.isActive ? 1 : 0; }
void chromeHideApp(void) { [NSApp hide:nil]; }

static NSWindow *win(void *root) { return ((__bridge NSView *)root).window; }

int chromeWindowIsKey(void *root) { return win(root).isKeyWindow ? 1 : 0; }
int chromeWindowNumber(void *root) { return (int)win(root).windowNumber; }
int chromeSharingType(void *root) { return (int)win(root).sharingType; }

static atomic_int s_auth = -1;
static NSSet<NSString *> *s_delivered = nil;

void chromeNotifyQuery(void) {
    UNUserNotificationCenter *c = [UNUserNotificationCenter currentNotificationCenter];
    atomic_store(&s_auth, -1);
    @synchronized ([UNUserNotificationCenter class]) { s_delivered = nil; }
    [c getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *s) {
        atomic_store(&s_auth, (int)s.authorizationStatus);
    }];
    [c getDeliveredNotificationsWithCompletionHandler:^(NSArray<UNNotification *> *list) {
        NSMutableSet *ids = [NSMutableSet set];
        for (UNNotification *n in list) [ids addObject:n.request.identifier];
        @synchronized ([UNUserNotificationCenter class]) { s_delivered = ids; }
    }];
}

int chromeNotifyAuth(void) { return atomic_load(&s_auth); }

int chromeNotifyDelivered(const char *id) {
    @synchronized ([UNUserNotificationCenter class]) {
        if (s_delivered == nil) return -1;
        return [s_delivered containsObject:[NSString stringWithUTF8String:id]] ? 1 : 0;
    }
}

static int s_cancelledOpenPanel = 0;

void chromeCancelModalAfter(int ms) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)ms * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        NSWindow *m = NSApp.modalWindow;
        s_cancelledOpenPanel = [m isKindOfClass:[NSOpenPanel class]] ? 1 : 0;
        if ([m isKindOfClass:[NSSavePanel class]]) [(NSSavePanel *)m cancel:nil];
        else [NSApp abortModal];
    });
}

int chromeCancelledOpenPanel(void) { return s_cancelledOpenPanel; }
