// Ion macOS — menu-bar (tray) status item.
//
// Single tray per app. Click → "tray.click" IPC message + bring main window
// to front. Image variant marks the PNG as a template image so it auto-
// adapts to dark/light menu bar.
//
// Path resolution for installTrayImage: try literal path first, then look
// up by filename in NSBundle.mainBundle's Resources/. Lets callers pass
// "tray-icon.png" both in dev (cwd-relative) and in a packaged .app.

#import "../state.h"
#import "../../bridge.h"
#import <Cocoa/Cocoa.h>

@interface IonTrayTarget : NSObject
- (void)trayClicked:(id)sender;
@end

@implementation IonTrayTarget
- (void)trayClicked:(id)sender {
    ionEnqueueMessage(@"tray.click", @"");
    [NSApp activateIgnoringOtherApps:YES];
    if (s_nsWindow) [s_nsWindow makeKeyAndOrderFront:nil];
}
@end

static NSStatusItem    *s_tray       = nil;
static IonTrayTarget   *s_trayTarget = nil;

static void ensureTray(void) {
    if (s_tray != nil) return;
    s_trayTarget = [[IonTrayTarget alloc] init];
    s_tray = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    s_tray.button.target = s_trayTarget;
    s_tray.button.action = @selector(trayClicked:);
}

void ionInstallTray(const char *title) {
    ensureTray();
    s_tray.button.image = nil;
    s_tray.button.title = (title && title[0]) ? [NSString stringWithUTF8String:title] : @"●";
}

static NSImage *loadImage(NSString *pathOrName) {
    NSImage *image = [[NSImage alloc] initWithContentsOfFile:pathOrName];
    if (image != nil) return image;
    NSString *res = [[NSBundle mainBundle] pathForResource:pathOrName.lastPathComponent
                                                    ofType:nil];
    if (res != nil) return [[NSImage alloc] initWithContentsOfFile:res];
    return nil;
}

void ionInstallTrayImage(const char *pngPath) {
    ensureTray();
    if (pngPath == NULL || pngPath[0] == '\0') {
        s_tray.button.image = nil;
        return;
    }
    NSImage *image = loadImage([NSString stringWithUTF8String:pngPath]);
    if (image == nil) {
        s_tray.button.title = @"●"; // fallback so the tray stays visible
        return;
    }
    image.template = YES;
    image.size = NSMakeSize(18, 18);
    s_tray.button.image = image;
    s_tray.button.title = @"";
}

void ionUninstallTray(void) {
    if (s_tray) {
        [[NSStatusBar systemStatusBar] removeStatusItem:s_tray];
        s_tray = nil;
    }
    s_trayTarget = nil;
}
