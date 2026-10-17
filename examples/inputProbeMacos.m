#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
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
