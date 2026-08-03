// Ion macOS — native menu bar.
//
// Standard 5-menu layout (App / File / Edit / View / Window) with the usual
// macOS keyboard shortcuts. Most actions go through the responder chain to
// either NSApp (terminate, hide), the focused NSWindow (close, miniaturize),
// or the focused NSResponder (cut/copy/paste/select all → WKWebView).
//
// Custom action: View → Reload routes to s_menuTarget which calls
// [s_webview reload].

#import "../state.h"
#import <Cocoa/Cocoa.h>

@interface IonMenuTarget : NSObject
- (void)reload:(id)sender;
@end

@implementation IonMenuTarget
- (void)reload:(id)sender {
    if (s_webview) [s_webview reload];
}
@end

static IonMenuTarget *s_menuTarget = nil;

static NSMenuItem *menuItem(NSString *title, SEL action, NSString *key) {
    return [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:key];
}

static NSMenu *buildMainMenu(NSString *appName) {
    NSMenu *root = [[NSMenu alloc] init];

    // App menu
    NSMenuItem *appItem = [[NSMenuItem alloc] init];
    NSMenu *appMenu = [[NSMenu alloc] init];
    [appMenu addItem:menuItem([NSString stringWithFormat:@"About %@", appName],
                              @selector(orderFrontStandardAboutPanel:), @"")];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItem:menuItem([NSString stringWithFormat:@"Hide %@", appName],
                              @selector(hide:), @"h")];
    NSMenuItem *hideOthers = menuItem(@"Hide Others",
                                       @selector(hideOtherApplications:), @"h");
    hideOthers.keyEquivalentModifierMask = NSEventModifierFlagOption | NSEventModifierFlagCommand;
    [appMenu addItem:hideOthers];
    [appMenu addItem:menuItem(@"Show All", @selector(unhideAllApplications:), @"")];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItem:menuItem([NSString stringWithFormat:@"Quit %@", appName],
                              @selector(terminate:), @"q")];
    appItem.submenu = appMenu;
    [root addItem:appItem];

    // File
    NSMenuItem *fileItem = [[NSMenuItem alloc] initWithTitle:@"File" action:nil keyEquivalent:@""];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    [fileMenu addItem:menuItem(@"Close Window", @selector(performClose:), @"w")];
    fileItem.submenu = fileMenu;
    [root addItem:fileItem];

    // Edit — responder chain auto-routes to webview
    NSMenuItem *editItem = [[NSMenuItem alloc] initWithTitle:@"Edit" action:nil keyEquivalent:@""];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItem:menuItem(@"Undo", @selector(undo:), @"z")];
    NSMenuItem *redoItem = menuItem(@"Redo", @selector(redo:), @"z");
    redoItem.keyEquivalentModifierMask = NSEventModifierFlagShift | NSEventModifierFlagCommand;
    [editMenu addItem:redoItem];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItem:menuItem(@"Cut", @selector(cut:), @"x")];
    [editMenu addItem:menuItem(@"Copy", @selector(copy:), @"c")];
    [editMenu addItem:menuItem(@"Paste", @selector(paste:), @"v")];
    [editMenu addItem:menuItem(@"Select All", @selector(selectAll:), @"a")];
    editItem.submenu = editMenu;
    [root addItem:editItem];

    // View
    NSMenuItem *viewItem = [[NSMenuItem alloc] initWithTitle:@"View" action:nil keyEquivalent:@""];
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
    NSMenuItem *reloadItem = menuItem(@"Reload", @selector(reload:), @"r");
    reloadItem.target = s_menuTarget;
    [viewMenu addItem:reloadItem];
    viewItem.submenu = viewMenu;
    [root addItem:viewItem];

    // Window
    NSMenuItem *winItem = [[NSMenuItem alloc] initWithTitle:@"Window" action:nil keyEquivalent:@""];
    NSMenu *winMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    [winMenu addItem:menuItem(@"Minimize", @selector(performMiniaturize:), @"m")];
    [winMenu addItem:menuItem(@"Zoom", @selector(performZoom:), @"")];
    winItem.submenu = winMenu;
    [root addItem:winItem];
    [NSApp setWindowsMenu:winMenu];

    return root;
}

static BOOL s_menuInstalled = NO;

void ionEnsureMenu(NSString *appName) {
    if (s_menuInstalled) return;
    if (s_menuTarget == nil) s_menuTarget = [[IonMenuTarget alloc] init];
    [NSApp setMainMenu:buildMainMenu(appName)];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    s_menuInstalled = YES;
}
