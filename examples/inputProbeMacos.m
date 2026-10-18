#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <Carbon/Carbon.h>
#include "inputProbeMacos.h"

static NSWindow *win(void *root) { return ((__bridge NSView *)root).window; }

static NSPoint windowPoint(void *root, int x, int y) {
    NSView *content = (__bridge NSView *)root;
    CGFloat scale = content.window.backingScaleFactor;
    NSPoint p = NSMakePoint(x / scale, content.isFlipped ? y / scale : content.bounds.size.height - y / scale);
    return [content convertPoint:p toView:nil];
}

static NSEventModifierFlags flags(int mods) {
    NSEventModifierFlags f = 0;
    if (mods & 1) f |= NSEventModifierFlagShift;
    if (mods & 2) f |= NSEventModifierFlagControl;
    if (mods & 4) f |= NSEventModifierFlagOption;
    if (mods & 8) f |= NSEventModifierFlagCommand;
    return f;
}

static void post(NSEvent *e) { [NSApp postEvent:e atStart:NO]; }

void ipActivate(void *root) {
    [NSApp activateIgnoringOtherApps:YES];
    [win(root) makeKeyAndOrderFront:nil];
}

void ipClick(void *root, int x, int y, int button, int mods) {
    NSEventType down = button == 1 ? NSEventTypeLeftMouseDown : button == 2 ? NSEventTypeRightMouseDown : NSEventTypeOtherMouseDown;
    NSEventType up = button == 1 ? NSEventTypeLeftMouseUp : button == 2 ? NSEventTypeRightMouseUp : NSEventTypeOtherMouseUp;
    NSPoint p = windowPoint(root, x, y);
    NSInteger n = win(root).windowNumber;
    for (int i = 0; i < 2; i++) {
        post([NSEvent mouseEventWithType:(i == 0 ? down : up) location:p modifierFlags:flags(mods)
                                timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:n
                                  context:nil eventNumber:0 clickCount:1 pressure:(i == 0 ? 1 : 0)]);
    }
}

// A device event as AppKit builds it for this window and point (window number and window
// location are set; neither can be set on a CGEvent through the public API), retyped as `type`.
static CGEventRef deviceEvent(void *root, int x, int y, CGEventType type, int mods) {
    NSEvent *e = [NSEvent mouseEventWithType:NSEventTypeMouseMoved location:windowPoint(root, x, y)
                               modifierFlags:flags(mods) timestamp:NSProcessInfo.processInfo.systemUptime
                                windowNumber:win(root).windowNumber context:nil eventNumber:0 clickCount:0 pressure:0];
    CGEventRef c = CGEventCreateCopy(e.CGEvent);
    CGEventSetType(c, type);
    return c;
}

static void postCG(CGEventRef e) {
    post([NSEvent eventWithCGEvent:e]);
    CFRelease(e);
}

void ipButton(void *root, int x, int y, int button, int mods) {
    CGEventType down = button == 1 ? kCGEventLeftMouseDown : button == 2 ? kCGEventRightMouseDown : kCGEventOtherMouseDown;
    CGEventType up = button == 1 ? kCGEventLeftMouseUp : button == 2 ? kCGEventRightMouseUp : kCGEventOtherMouseUp;
    for (int i = 0; i < 2; i++) {
        CGEventRef e = deviceEvent(root, x, y, i == 0 ? down : up, mods);
        CGEventSetIntegerValueField(e, kCGMouseEventButtonNumber, button - 1);
        CGEventSetIntegerValueField(e, kCGMouseEventClickState, 1);
        postCG(e);
    }
}

void ipMove(void *root, int x, int y, int mods) {
    postCG(deviceEvent(root, x, y, kCGEventMouseMoved, mods));
}

// Axis 1 is vertical (positive away from the user), axis 2 horizontal (positive to the left).
void ipScroll(void *root, int x, int y, int unitPixels, int down, int right, int mods) {
    CGEventRef e = deviceEvent(root, x, y, kCGEventScrollWheel, mods);
    CGEventSetIntegerValueField(e, kCGScrollWheelEventIsContinuous, unitPixels);
    if (unitPixels) {
        CGEventSetIntegerValueField(e, kCGScrollWheelEventPointDeltaAxis1, -down);
        CGEventSetIntegerValueField(e, kCGScrollWheelEventPointDeltaAxis2, -right);
    } else {
        CGEventSetIntegerValueField(e, kCGScrollWheelEventDeltaAxis1, -down);
        CGEventSetIntegerValueField(e, kCGScrollWheelEventDeltaAxis2, -right);
    }
    postCG(e);
}

// The window server sends mouseExited from a tracking area; a posted exit event carries that
// area as its tracking number, which is how AppKit routes it to the area's owner.
void ipLeave(void *root, int mods) {
    NSView *content = (__bridge NSView *)root;
    for (NSView *v in content.subviews) {
        if (![NSStringFromClass(v.class) isEqualToString:@"IonContentHost"]) continue;
        NSTrackingArea *ta = v.trackingAreas.firstObject;
        for (int i = 0; i < 2; i++) {
            post([NSEvent enterExitEventWithType:(i == 0 ? NSEventTypeMouseEntered : NSEventTypeMouseExited)
                                        location:NSMakePoint(-1, -1) modifierFlags:flags(mods)
                                       timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:win(root).windowNumber
                                         context:nil eventNumber:0 trackingNumber:(NSInteger)ta userData:NULL]);
        }
        return;
    }
    fprintf(stderr, "probe: no IonContentHost\n");
}

void ipKey(void *root, int keyCode, const char *chars, const char *bare, int mods) {
    NSInteger n = win(root).windowNumber;
    NSString *c = @(chars), *b = @(bare);
    for (int i = 0; i < 2; i++) {
        post([NSEvent keyEventWithType:(i == 0 ? NSEventTypeKeyDown : NSEventTypeKeyUp) location:NSZeroPoint
                         modifierFlags:flags(mods) timestamp:NSProcessInfo.processInfo.systemUptime
                          windowNumber:n context:nil characters:c charactersIgnoringModifiers:b
                             isARepeat:NO keyCode:(unsigned short)keyCode]);
    }
}

void ipMarked(void *root, const char *utf8, int caretUtf16) {
    id<NSTextInputClient> client = (id<NSTextInputClient>)win(root).firstResponder;
    [client setMarkedText:@(utf8) selectedRange:NSMakeRange(caretUtf16, 0) replacementRange:NSMakeRange(NSNotFound, 0)];
}

void ipCommit(void *root, const char *utf8) {
    id<NSTextInputClient> client = (id<NSTextInputClient>)win(root).firstResponder;
    [client insertText:@(utf8) replacementRange:NSMakeRange(NSNotFound, 0)];
}

int ipWebviewIsFirstResponder(void *root) {
    NSResponder *r = win(root).firstResponder;
    if (![r isKindOfClass:[NSView class]]) return 0;
    for (NSView *v = (NSView *)r; v != nil; v = v.superview) {
        if ([v isKindOfClass:[WKWebView class]]) return 1;
    }
    return 0;
}

static TISInputSourceRef s_previousSource = NULL;
static NSMutableArray *s_enabledHere = nil;

static TISInputSourceRef installedSource(NSString *sourceId) {
    NSDictionary *filter = @{ (__bridge NSString *)kTISPropertyInputSourceID: sourceId };
    NSArray *found = CFBridgingRelease(TISCreateInputSourceList((__bridge CFDictionaryRef)filter, true));
    return found.count ? (__bridge TISInputSourceRef)found[0] : NULL;
}

static int enable(TISInputSourceRef source) {
    if (CFBooleanGetValue(TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled))) return 1;
    if (TISEnableInputSource(source) != noErr) return 0;
    [s_enabledHere addObject:(__bridge id)source];
    return 1;
}

// An input mode (com.apple.inputmethod.X.Mode) is selectable only once its input method
// (com.apple.inputmethod.X) is enabled too.
int ipSelectInputSource(const char *sourceId) {
    NSString *mode = @(sourceId);
    TISInputSourceRef source = installedSource(mode);
    if (source == NULL) return 0;
    if (s_previousSource == NULL) s_previousSource = TISCopyCurrentKeyboardInputSource();
    if (s_enabledHere == nil) s_enabledHere = [NSMutableArray array];
    TISInputSourceRef method = installedSource([mode stringByDeletingPathExtension]);
    if ((method != NULL && !enable(method)) || !enable(source)) return 0;
    OSStatus st = TISSelectInputSource(source);
    return st == noErr;
}

// NSEvent takes its window from this undocumented CGEvent field (found by reading a
// mouseEventWithType: event back, macOS 26.6); without it the key event has no window.
static const CGEventField kWindowNumberField = (CGEventField)51;

void ipDeviceKey(void *root, int keyCode) {
    for (int i = 0; i < 2; i++) {
        CGEventRef e = CGEventCreateKeyboardEvent(NULL, (CGKeyCode)keyCode, i == 0);
        CGEventSetIntegerValueField(e, kCGKeyboardEventKeyboardType, LMGetKbdType());
        CGEventSetIntegerValueField(e, kWindowNumberField, win(root).windowNumber);
        post([NSEvent eventWithCGEvent:e]);
        CFRelease(e);
    }
}

int ipAppActive(void *root) {
    return NSApp.isActive && win(root).isKeyWindow;
}

void ipRestoreInputSource(void) {
    if (s_previousSource != NULL) {
        TISSelectInputSource(s_previousSource);
        CFRelease(s_previousSource);
        s_previousSource = NULL;
    }
    for (id source in s_enabledHere.reverseObjectEnumerator) TISDisableInputSource((__bridge TISInputSourceRef)source);
    s_enabledHere = nil;
}
