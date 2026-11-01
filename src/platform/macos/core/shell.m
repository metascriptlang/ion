// Ion macOS — open a URL in the user's default handler (system browser).
// Mirrors the external-link path in webview/nav_delegate.m, exposed as a
// first-class bridge call so MS apps can launch OAuth consent pages etc.

#import <Cocoa/Cocoa.h>

int ionOpenExternal(const char *url) {
    if (url == NULL || url[0] == '\0') return 0;
    NSString *s = [NSString stringWithUTF8String:url];
    NSURL *u = s == nil ? nil : [NSURL URLWithString:s];
    if (u == nil) return 0;
    return [[NSWorkspace sharedWorkspace] openURL:u] ? 1 : 0;
}
