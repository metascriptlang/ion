// Ion macOS — native menu bar.
//
// The app's bar from ionMenuBegin … ionMenuCommit, or else Ion's standard 5-menu layout
// (App / File / Edit / View / Window), installed with the first window. Role items act
// through the responder chain to either NSApp (terminate, hide), the focused NSWindow
// (close, miniaturize), or the focused NSResponder (cut/copy/paste/select all → WKWebView).
//
// Custom actions route to s_menuTarget: View → Reload calls [view reload] on every
// webview, and an app item enqueues "menu.click" with its id.

#import "../state.h"
#import "../../bridge.h"
#include "../../common/webviewRegistry.h"
#import <Cocoa/Cocoa.h>

@interface IonMenuTarget : NSObject
- (void)reload:(id)sender;
- (void)click:(NSMenuItem *)sender;
@end

@implementation IonMenuTarget
- (void)reload:(id)sender {
    for (int wv = ion_webview_next(-1); wv != ION_WEBVIEW_INVALID; wv = ion_webview_next(wv)) {
        [ionMacWebviewState(wv)->view reload];
    }
}

- (void)click:(NSMenuItem *)sender {
    ionEnqueueMessage(@"menu.click", sender.representedObject);
}
@end

static IonMenuTarget *s_menuTarget = nil;

static IonMenuTarget *menuTarget(void) {
    if (s_menuTarget == nil) s_menuTarget = [[IonMenuTarget alloc] init];
    return s_menuTarget;
}

static NSMenuItem *menuItem(NSString *title, SEL action, NSString *key) {
    return [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:key];
}

static NSMenuItem *withMods(NSMenuItem *item, NSEventModifierFlags mods) {
    item.keyEquivalentModifierMask = mods;
    return item;
}

static NSMenuItem *roleItem(int role, NSString *appName) {
    const NSEventModifierFlags cmd = NSEventModifierFlagCommand;
    switch (role) {
        case ION_MENU_ROLE_ABOUT:
            return menuItem([NSString stringWithFormat:@"About %@", appName],
                            @selector(orderFrontStandardAboutPanel:), @"");
        case ION_MENU_ROLE_HIDE:
            return menuItem([NSString stringWithFormat:@"Hide %@", appName], @selector(hide:), @"h");
        case ION_MENU_ROLE_HIDE_OTHERS:
            return withMods(menuItem(@"Hide Others", @selector(hideOtherApplications:), @"h"),
                            NSEventModifierFlagOption | cmd);
        case ION_MENU_ROLE_SHOW_ALL:
            return menuItem(@"Show All", @selector(unhideAllApplications:), @"");
        case ION_MENU_ROLE_QUIT:
            return menuItem([NSString stringWithFormat:@"Quit %@", appName], @selector(terminate:), @"q");
        case ION_MENU_ROLE_CLOSE_WINDOW:
            return menuItem(@"Close Window", @selector(performClose:), @"w");
        case ION_MENU_ROLE_MINIMIZE:
            return menuItem(@"Minimize", @selector(performMiniaturize:), @"m");
        case ION_MENU_ROLE_ZOOM:
            return menuItem(@"Zoom", @selector(performZoom:), @"");
        case ION_MENU_ROLE_FULLSCREEN:
            return withMods(menuItem(@"Enter Full Screen", @selector(toggleFullScreen:), @"f"),
                            NSEventModifierFlagControl | cmd);
        case ION_MENU_ROLE_UNDO:
            return menuItem(@"Undo", @selector(undo:), @"z");
        case ION_MENU_ROLE_REDO:
            return withMods(menuItem(@"Redo", @selector(redo:), @"z"), NSEventModifierFlagShift | cmd);
        case ION_MENU_ROLE_CUT:
            return menuItem(@"Cut", @selector(cut:), @"x");
        case ION_MENU_ROLE_COPY:
            return menuItem(@"Copy", @selector(copy:), @"c");
        case ION_MENU_ROLE_PASTE:
            return menuItem(@"Paste", @selector(paste:), @"v");
        case ION_MENU_ROLE_SELECT_ALL:
            return menuItem(@"Select All", @selector(selectAll:), @"a");
        case ION_MENU_ROLE_RELOAD: {
            NSMenuItem *item = menuItem(@"Reload", @selector(reload:), @"r");
            item.target = menuTarget();
            return item;
        }
        default:
            return nil;
    }
}

static NSMenuItem *submenuItem(NSString *title, NSMenu *menu) {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
    item.submenu = menu;
    return item;
}

#define ROLES(a) a, (int)(sizeof a / sizeof a[0])

static NSMenu *roleMenu(NSString *title, const int *roles, int count, NSString *appName) {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:title];
    for (int i = 0; i < count; i++) {
        [menu addItem:roles[i] < 0 ? [NSMenuItem separatorItem] : roleItem(roles[i], appName)];
    }
    return menu;
}

static NSMenu *buildMainMenu(NSString *appName) {
    enum { SEP = -1 };
    static const int app[] = { ION_MENU_ROLE_ABOUT, SEP, ION_MENU_ROLE_HIDE, ION_MENU_ROLE_HIDE_OTHERS,
                               ION_MENU_ROLE_SHOW_ALL, SEP, ION_MENU_ROLE_QUIT };
    static const int file[] = { ION_MENU_ROLE_CLOSE_WINDOW };
    // Edit — responder chain auto-routes to webview
    static const int edit[] = { ION_MENU_ROLE_UNDO, ION_MENU_ROLE_REDO, SEP, ION_MENU_ROLE_CUT,
                                ION_MENU_ROLE_COPY, ION_MENU_ROLE_PASTE, ION_MENU_ROLE_SELECT_ALL };
    static const int view[] = { ION_MENU_ROLE_RELOAD };
    static const int window[] = { ION_MENU_ROLE_MINIMIZE, ION_MENU_ROLE_ZOOM };

    NSMenu *root = [[NSMenu alloc] init];
    [root addItem:submenuItem(@"", roleMenu(@"", ROLES(app), appName))];
    [root addItem:submenuItem(@"File", roleMenu(@"File", ROLES(file), appName))];
    [root addItem:submenuItem(@"Edit", roleMenu(@"Edit", ROLES(edit), appName))];
    [root addItem:submenuItem(@"View", roleMenu(@"View", ROLES(view), appName))];
    NSMenu *winMenu = roleMenu(@"Window", ROLES(window), appName);
    [root addItem:submenuItem(@"Window", winMenu)];
    [NSApp setWindowsMenu:winMenu];
    return root;
}

static BOOL s_menuInstalled = NO;
static NSMenu *s_appBar = nil;
static NSMenu *s_pendingBar = nil;
static NSMenu *s_pendingSubmenu = nil;

void ionEnsureMenu(NSString *appName) {
    if (s_menuInstalled) return;
    [NSApp setMainMenu:s_appBar != nil ? s_appBar : buildMainMenu(appName)];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    s_menuInstalled = YES;
}

static NSString *appMenuName(void) {
    return NSRunningApplication.currentApplication.localizedName;
}

static NSString *utf8(const char *s) {
    return [NSString stringWithUTF8String:s ? s : ""];
}

static NSString *keyEquivalent(NSString *key) {
    if (key.length == 0) return @"";
    if ([key rangeOfComposedCharacterSequenceAtIndex:0].length == key.length) return key.lowercaseString;
    NSString *name = key.lowercaseString;
    if ([name hasPrefix:@"f"] && name.length <= 3) {
        int n = [name substringFromIndex:1].intValue;
        NSString *digits = [NSString stringWithFormat:@"f%d", n];
        if (n >= 1 && n <= 12 && [digits isEqualToString:name]) {
            unichar c = (unichar)(NSF1FunctionKey + n - 1);
            return [NSString stringWithCharacters:&c length:1];
        }
    }
    NSDictionary<NSString *, NSNumber *> *named = @{
        @"space": @' ', @"return": @'\r', @"enter": @'\r', @"tab": @'\t',
        @"escape": @0x1b, @"esc": @0x1b, @"delete": @0x08, @"backspace": @0x08,
        @"up": @(NSUpArrowFunctionKey), @"down": @(NSDownArrowFunctionKey),
        @"left": @(NSLeftArrowFunctionKey), @"right": @(NSRightArrowFunctionKey),
    };
    NSNumber *code = named[name];
    if (code == nil) return nil;
    unichar c = (unichar)code.unsignedShortValue;
    return [NSString stringWithCharacters:&c length:1];
}

// Mirror mods.ms.
static NSEventModifierFlags modifierMask(int modifiers) {
    NSEventModifierFlags mask = 0;
    if (modifiers & 1) mask |= NSEventModifierFlagCommand;
    if (modifiers & 2) mask |= NSEventModifierFlagShift;
    if (modifiers & 4) mask |= NSEventModifierFlagOption;
    if (modifiers & 8) mask |= NSEventModifierFlagControl;
    return mask;
}

int ionMenuBegin(void) {
    s_pendingBar = [[NSMenu alloc] init];
    s_pendingSubmenu = nil;
    return 0;
}

int ionMenuAddSubmenu(const char *title) {
    s_pendingSubmenu = [[NSMenu alloc] initWithTitle:utf8(title)];
    [s_pendingBar addItem:submenuItem(utf8(title), s_pendingSubmenu)];
    return 0;
}

int ionMenuAddItem(const char *itemId, const char *title, const char *key, int modifiers) {
    NSString *equivalent = keyEquivalent(utf8(key));
    if (equivalent == nil) return ION_MENU_UNKNOWN_KEY;
    NSMenuItem *item = menuItem(utf8(title), @selector(click:), equivalent);
    item.keyEquivalentModifierMask = modifierMask(modifiers);
    item.target = menuTarget();
    item.representedObject = utf8(itemId);
    [s_pendingSubmenu addItem:item];
    return 0;
}

int ionMenuAddRole(int role) {
    NSMenuItem *item = roleItem(role, appMenuName());
    if (item == nil) return ION_MENU_UNKNOWN_ROLE;
    [s_pendingSubmenu addItem:item];
    return 0;
}

int ionMenuAddSeparator(void) {
    [s_pendingSubmenu addItem:[NSMenuItem separatorItem]];
    return 0;
}

int ionMenuCommit(void) {
    s_appBar = s_pendingBar;
    s_pendingBar = nil;
    s_pendingSubmenu = nil;
    if (s_menuInstalled) [NSApp setMainMenu:s_appBar];
    return 0;
}
