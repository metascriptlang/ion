#import <Cocoa/Cocoa.h>
#include "content.h"

// A native view takes the clicks it covers, as on Windows where the app's hit-test decides:
// an NSView that leaves mouseDown to its responder chain lets the webview under it get the
// click (measured with examples/contentInputMacos.ms).
@interface ContentPanel : NSView
@end

@implementation ContentPanel
- (void)mouseDown:(NSEvent *)e {}
- (void)rightMouseDown:(NSEvent *)e {}
- (void)otherMouseDown:(NSEvent *)e {}
@end

int contentAttach(void *parent, void *child, int above) {
    if (parent == NULL || child == NULL) return 0;
    NSView *p = (__bridge NSView *)parent;
    NSView *c = (__bridge NSView *)child;
    [p addSubview:c positioned:(above ? NSWindowAbove : NSWindowBelow) relativeTo:nil];
    return 1;
}

void contentDetach(void *parent, void *child) {
    (void)parent;
    if (child != NULL) [(__bridge NSView *)child removeFromSuperview];
}

void contentMove(void *node, int x, int y, int w, int h) {
    if (node == NULL) return;
    NSView *v = (__bridge NSView *)node;
    NSView *p = v.superview;
    CGFloat scale = p.window ? p.window.backingScaleFactor : 1.0;
    CGFloat height = p ? p.bounds.size.height : 0;
    NSRect frame = NSMakeRect(x / scale, height - (y + h) / scale, w / scale, h / scale);
    if (p.isFlipped) frame.origin.y = y / scale;
    v.frame = frame;
}

void *contentPanel(void *device, int w, int h, const char *text, unsigned rgb) {
    (void)device;
    NSView *panel = [[ContentPanel alloc] initWithFrame:NSMakeRect(0, 0, w, h)];
    panel.wantsLayer = YES;
    panel.layer.backgroundColor = [NSColor colorWithSRGBRed:((rgb >> 16) & 0xff) / 255.0
                                                      green:((rgb >> 8) & 0xff) / 255.0
                                                       blue:(rgb & 0xff) / 255.0
                                                      alpha:1].CGColor;
    NSTextField *label = [NSTextField labelWithString:@(text)];
    label.textColor = NSColor.whiteColor;
    label.frame = NSMakeRect(12, 12, 400, 22);
    [panel addSubview:label];
    return (__bridge void *)panel;
}

void contentRelease(void *node) {
    if (node != NULL) [(__bridge NSView *)node release];
}
