#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#include "servicesMacos.h"

void svActivate(void) { [NSApp activateIgnoringOtherApps:YES]; }

int svWebviewHasFocus(void) {
    NSResponder *r = NSApp.keyWindow.firstResponder;
    if (![r isKindOfClass:[NSView class]]) return 0;
    for (NSView *v = (NSView *)r; v != nil; v = v.superview) {
        if ([v isKindOfClass:[WKWebView class]]) return 1;
    }
    return 0;
}

const char *svFirstResponderClass(void) {
    NSResponder *r = NSApp.keyWindow.firstResponder;
    return r == nil ? "nil" : NSStringFromClass([r class]).UTF8String;
}

static NSSet<NSWindow *> *s_before = nil;
static NSMutableString *s_shareSeen = nil;

static NSArray<NSWindow *> *addedWindows(void) {
    NSMutableArray *out = [NSMutableArray array];
    for (NSWindow *w in NSApp.windows) {
        if (w.isVisible && ![s_before containsObject:w]) [out addObject:w];
    }
    return out;
}

static void afterMs(int ms, void (^block)(void)) {
    NSTimer *t = [NSTimer timerWithTimeInterval:ms / 1000.0 repeats:NO block:^(NSTimer *timer) {
        (void)timer;
        block();
    }];
    [[NSRunLoop mainRunLoop] addTimer:t forMode:NSRunLoopCommonModes];
    [[NSRunLoop mainRunLoop] addTimer:t forMode:NSModalPanelRunLoopMode];
}

static void dismissWhenShown(int msLeft) {
    NSArray<NSWindow *> *added = addedWindows();
    if (added.count == 0 && msLeft > 0) {
        afterMs(100, ^{ dismissWhenShown(msLeft - 100); });
        return;
    }
    for (NSWindow *w in added) {
        [s_shareSeen appendFormat:@"%@%@", s_shareSeen.length ? @"," : @"", NSStringFromClass([w class])];
        NSEvent *esc = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0
            timestamp:0 windowNumber:w.windowNumber context:nil characters:@"\e"
            charactersIgnoringModifiers:@"\e" isARepeat:NO keyCode:53];
        [w sendEvent:esc];
        if (w.isVisible) [w orderOut:nil];
    }
}

void svDismissShareWithin(int ms) {
    s_before = [NSSet setWithArray:NSApp.windows];
    s_shareSeen = [NSMutableString string];
    afterMs(100, ^{ dismissWhenShown(ms); });
}

const char *svShareWindowsSeen(void) { return s_shareSeen.UTF8String ?: ""; }
int svShareWindowsLeft(void) { return (int)addedWindows().count; }

static NSString *s_alertSeen = @"";

static NSButton *findButton(NSView *v, NSString *title) {
    if ([v isKindOfClass:[NSButton class]] && [((NSButton *)v).title isEqualToString:title]) return (NSButton *)v;
    for (NSView *sub in v.subviews) {
        NSButton *b = findButton(sub, title);
        if (b != nil) return b;
    }
    return nil;
}

static void collectButtons(NSView *v, NSMutableArray<NSString *> *out) {
    if ([v isKindOfClass:[NSButton class]] && ((NSButton *)v).title.length) [out addObject:((NSButton *)v).title];
    for (NSView *sub in v.subviews) collectButtons(sub, out);
}

void svAnswerAlertAfter(int ms, const char *title) {
    NSString *want = title[0] ? [NSString stringWithUTF8String:title] : nil;
    afterMs(ms, ^{
        NSWindow *m = NSApp.modalWindow;
        NSMutableArray<NSString *> *labels = [NSMutableArray array];
        collectButtons(m.contentView, labels);
        NSAlert *alert = nil;
        if ([m.delegate isKindOfClass:[NSAlert class]]) alert = (NSAlert *)m.delegate;
        s_alertSeen = [NSString stringWithFormat:@"%ld:%@", alert ? (long)alert.alertStyle : -1L,
                       [labels componentsJoinedByString:@"|"]];
        NSButton *b = want ? findButton(m.contentView, want) : nil;
        if (b != nil) [b performClick:nil];
        else [NSApp abortModal];
    });
}

const char *svAlertSeen(void) { return s_alertSeen.UTF8String; }
