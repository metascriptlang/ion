#import <Cocoa/Cocoa.h>
#include "windowFrameProbe.h"

void *ionWindowRoot(int id);

static NSWindow *windowOf(int id) { return ((__bridge NSView *)ionWindowRoot(id)).window; }

// Renders the content view's layer tree, where SDL3View paints its layer background.
int wpPixel(int window, int x, int y) {
    CALayer *layer = windowOf(window).contentView.layer;
    if (layer == nil) return -1;
    unsigned char px[4] = {0};
    CGColorSpaceRef rgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef ctx = CGBitmapContextCreate(px, 1, 1, 8, 4, rgb, kCGImageAlphaPremultipliedLast);
    CGContextTranslateCTM(ctx, -x, -(layer.bounds.size.height - y - 1));
    [layer renderInContext:ctx];
    CGContextRelease(ctx);
    CGColorSpaceRelease(rgb);
    return (px[0] << 16) | (px[1] << 8) | px[2];
}

int wpZoomed(int window) { return windowOf(window).isZoomed; }
int wpVisible(int window) { return windowOf(window).isVisible; }

int wpSteps(int window, int cellW, int cellH, int baseW, int baseH) {
    (void)baseW; (void)baseH;
    NSWindow *w = windowOf(window);
    NSSize inc = w.contentResizeIncrements;
    CGFloat scale = w.backingScaleFactor;
    return fabs(inc.width - cellW / scale) < 0.001 && fabs(inc.height - cellH / scale) < 0.001;
}

int wpOnScreen(int x, int y) {
    CGFloat top = NSScreen.screens[0].frame.size.height;
    NSPoint p = NSMakePoint(x + 1, top - y - 1);
    for (NSScreen *s in NSScreen.screens)
        if (NSPointInRect(p, s.frame)) return 1;
    return 0;
}

