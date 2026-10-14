#import <Cocoa/Cocoa.h>
#include "content.h"
#include <stdio.h>

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
    (void)device; (void)w; (void)h; (void)rgb;
    fprintf(stderr, "[content] contentPanel('%s'): drawn panels are Windows-only in this example\n", text);
    return NULL;
}

void contentRelease(void *node) { (void)node; }
