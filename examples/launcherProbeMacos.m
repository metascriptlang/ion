#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>
#include <stdlib.h>
#include <objc/runtime.h>
#include <objc/message.h>
#include "launcherProbeMacos.h"

static NSWindow *win(void *root) { return ((__bridge NSView *)root).window; }

const char *lpFrontApp(void) {
    NSString *name = NSWorkspace.sharedWorkspace.frontmostApplication.localizedName ?: @"";
    return strdup(name.UTF8String);
}

static pid_t s_remembered;

void lpRememberFront(void) {
    s_remembered = NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier;
}

int lpAboveRemembered(void *root) {
    NSInteger ours = win(root).windowNumber;
    NSArray *list = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID));
    for (NSDictionary *w in list) {
        if ([w[(id)kCGWindowLayer] intValue] != 0) continue;
        if ([w[(id)kCGWindowNumber] integerValue] == ours) return 1;
        if ([w[(id)kCGWindowOwnerPID] intValue] == s_remembered) return 0;
    }
    return 0;
}

int lpOnScreen(void *root) { return win(root).isVisible ? 1 : 0; }

int lpKeyState(void *root) {
    if (!win(root).isKeyWindow) return 0;
    return NSApp.isActive ? 2 : 1;
}

void lpPostKey(int keyCode, int command, int option, int control) {
    CGEventFlags f = 0;
    if (command) f |= kCGEventFlagMaskCommand;
    if (option)  f |= kCGEventFlagMaskAlternate;
    if (control) f |= kCGEventFlagMaskControl;
    for (int down = 1; down >= 0; down--) {
        CGEventRef e = CGEventCreateKeyboardEvent(NULL, (CGKeyCode)keyCode, down);
        CGEventSetFlags(e, f);
        CGEventPost(kCGHIDEventTap, e);
        CFRelease(e);
    }
}

int lpTrusted(void) { return AXIsProcessTrusted() ? 1 : 0; }

void lpSpawn(const char *role) {
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:NSProcessInfo.processInfo.arguments[0]];
    NSMutableDictionary *env = [NSProcessInfo.processInfo.environment mutableCopy];
    env[@"LAUNCHER_ROLE"] = @(role);
    task.environment = env;
    task.standardOutput = NSFileHandle.fileHandleWithNullDevice;
    [task launchAndReturnError:nil];
}

void lpClickRemembered(void) {
    NSArray *list = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID));
    for (NSDictionary *w in list) {
        if ([w[(id)kCGWindowLayer] intValue] != 0 || [w[(id)kCGWindowOwnerPID] intValue] != s_remembered) continue;
        CGRect r;
        CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)w[(id)kCGWindowBounds], &r);
        CGPoint p = CGPointMake(CGRectGetMidX(r), CGRectGetMaxY(r) - 40);
        CGEventType types[2] = { kCGEventLeftMouseDown, kCGEventLeftMouseUp };
        for (int i = 0; i < 2; i++) {
            CGEventRef e = CGEventCreateMouseEvent(NULL, types[i], p, kCGMouseButtonLeft);
            CGEventPost(kCGHIDEventTap, e);
            CFRelease(e);
        }
        return;
    }
}

int lpRememberedInFront(void) {
    return NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier == s_remembered;
}

int lpFrontIsOther(void) {
    return NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier != getpid();
}

int lpOnActiveSpace(void *root) { return win(root).isOnActiveSpace ? 1 : 0; }

static NSWindowStyleMask panelStyleMask(id self, SEL _cmd) {
    struct objc_super sup = { self, class_getSuperclass(object_getClass(self)) };
    NSWindowStyleMask (*send)(struct objc_super *, SEL) = (void *)objc_msgSendSuper;
    return send(&sup, _cmd) | NSWindowStyleMaskNonactivatingPanel;
}

void lpConfigure(void *root, const char *mode) {
    NSWindow *w = win(root);
    NSString *m = @(mode);
    if (m.length == 0) return;
    NSWindowCollectionBehavior b = w.collectionBehavior | NSWindowCollectionBehaviorCanJoinAllSpaces;
    if (![m isEqualToString:@"spaces"]) b |= NSWindowCollectionBehaviorFullScreenAuxiliary;
    w.collectionBehavior = b;
    if ([m isEqualToString:@"panel"]) {
        Class base = object_getClass(w);
        NSString *name = [NSStringFromClass(base) stringByAppendingString:@"_IonPanel"];
        Class sub = NSClassFromString(name);
        if (sub == nil) {
            sub = objc_allocateClassPair(base, name.UTF8String, 0);
            class_addMethod(sub, @selector(styleMask), (IMP)panelStyleMask, "Q@:");
            objc_registerClassPair(sub);
        }
        object_setClass(w, sub);
        w.level = NSFloatingWindowLevel;
    }
}

void lpFocusPanel(void *root) {
    [win(root) makeKeyAndOrderFront:nil];
}
