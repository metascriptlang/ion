// Ion macOS — open a URL in the user's default handler (system browser).
// Mirrors the external-link path in webview/nav_delegate.m, exposed as a
// first-class bridge call so MS apps can launch OAuth consent pages etc.

#import <Cocoa/Cocoa.h>

void ionOpenExternal(const char *url) {
    if (url == NULL || url[0] == '\0') return;
    NSString *s = [NSString stringWithUTF8String:url];
    NSURL *u = [NSURL URLWithString:s];
    if (u == nil) return;
    [[NSWorkspace sharedWorkspace] openURL:u];
}
