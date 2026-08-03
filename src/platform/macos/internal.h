// Ion macOS — platform-internal forward declarations.
//
// bridge.h is the public C API consumed by MS code (ionOpen, ionClose, ...).
// internal.h is the platform-private surface — symbols implemented in one .m
// file and called from another .m file in the same platform layer. Keeping
// these out of bridge.h makes the public/private distinction explicit and
// prevents MS-side accidental imports of platform internals.

#ifndef ION_MACOS_INTERNAL_H
#define ION_MACOS_INTERNAL_H

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#include "../common/strconv.h"  // cStringToMs (cross-platform)

// nsStringToMs — Cocoa-only NSString → msString bridge. nil/empty/non-UTF8
// collapses to MS_EMPTY_STRING (zero/NULL payload, no alloc). One stop for
// every macOS bridge fn that pipes Cocoa text back to MS land.
static inline msString nsStringToMs(NSString *s) {
    if (s == nil || s.length == 0) return MS_EMPTY_STRING;
    const char *utf8 = s.UTF8String;
    return utf8 ? msStringFromCStr(utf8) : MS_EMPTY_STRING;
}

// ipc/url_scheme.m
void       ionInstallURLHandler(void);

// chrome/menu.m
void       ionEnsureMenu(NSString *appName);

// webview/bootstrap.m
// `windowLabel` is injected as window.__ion__.label and tagged onto every
// JS→MS message envelope. Pass "" for legacy single-window builds.
WKWebView *ionSetupWebview(NSView *contentView, const char *windowLabel);

// webview/protocol.m
void       ionInstallSchemeHandlers(WKWebViewConfiguration *cfg);

#endif
