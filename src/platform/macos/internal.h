// Ion macOS — platform-internal forward declarations.
//
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

void       ionSyncFrameState(IonWindowId winId);
void       ionMacReleaseDestroyed(IonWindowId winId);
int        ionMacAllWindowsClosed(void);

// webview/poll.m — wakes the loop's wait; any thread
void       ionMacNudge(void);

// core/frame.m
void       ionMacFrameSync(void);
void       ionMacFrameDetach(NSView *host);
int        ionMacFrameTickPending(void);
int        ionMacFrameTakeTick(double *timeMs);

NSView    *ionContentHostCreate(IonWindowId winId, NSWindow *nsWindow);
void       ionContentHostDestroy(NSView *host);
void       ionContentHostSetCursor(NSView *host, int cursor);
void       ionContentHostSetImeRect(NSView *host, int x, int y, int w, int h);

// webview/bootstrap.m
WKWebView *ionSetupWebview(const char *label, int webviewId, id *navDelegateOut);

// webview/protocol.m
void       ionInstallSchemeHandlers(WKWebViewConfiguration *cfg);

#endif
