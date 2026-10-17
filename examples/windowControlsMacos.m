#import <Cocoa/Cocoa.h>
#include "windowControlsMacos.h"

static NSView *s_root;

void wcBind(void *root) { s_root = (__bridge NSView *)root; }

static NSWindow *win(void) { return s_root.window; }

int wcRootW(void) { return (int)s_root.bounds.size.width; }
int wcRootH(void) { return (int)s_root.bounds.size.height; }

int wcOuterX(void) { return (int)win().frame.origin.x; }
int wcOuterY(void) {
    NSRect f = win().frame;
    return (int)(NSScreen.screens[0].frame.size.height - (f.origin.y + f.size.height));
}

int wcTitleIs(const char *utf8) { return [win().title isEqualToString:@(utf8)]; }
int wcVisible(void) { return win().isVisible; }
int wcMinimized(void) { return win().isMiniaturized; }
int wcMaximized(void) { return win().isZoomed; }
int wcDecorated(void) { return (win().styleMask & NSWindowStyleMaskTitled) != 0; }
int wcTopmost(void) { return win().level > NSNormalWindowLevel; }
int wcActive(void) { return win().isKeyWindow; }

void wcUserClose(void) { [win() performClose:nil]; }
