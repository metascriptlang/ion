// Ion macOS — WKNavigationDelegate that routes external links to the system
// browser. Decision logic lives in src/platform/common/navpolicy.c — this
// file only adapts WebKit's API to that pure-C function.

#import "../state.h"
#import <WebKit/WebKit.h>
#import <Cocoa/Cocoa.h>
#include "../../common/navpolicy.h"

@interface IonNavigationDelegate : NSObject <WKNavigationDelegate>
@end

@implementation IonNavigationDelegate
- (void)webView:(WKWebView *)webView
    decidePolicyForNavigationAction:(WKNavigationAction *)action
                    decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *url = action.request.URL;
    if (url == nil) { decisionHandler(WKNavigationActionPolicyAllow); return; }

    const char *scheme = url.scheme.lowercaseString.UTF8String;
    const char *host   = url.host.UTF8String;
    int isUserClick    = action.navigationType == WKNavigationTypeLinkActivated ? 1 : 0;

    ion_nav_decision_t decision = ion_nav_decide(scheme, host, isUserClick);
    if (decision == ION_NAV_EXTERNAL) {
        [[NSWorkspace sharedWorkspace] openURL:url];
        decisionHandler(WKNavigationActionPolicyCancel);
    } else if (decision == ION_NAV_BLOCK) {
        // file:// is the only scheme we BLOCK today — opaque-origin trap.
        // Log clearly so app developers know what happened + how to fix.
        NSLog(@"[ion] navigation blocked: %@ — file:// has opaque origin which "
              @"breaks pushState/localStorage/SW. Use ion:// (bundled) or "
              @"asset:// (scoped) instead. See vendor/ion/CUSTOM-PROTOCOL.md",
              url.absoluteString);
        decisionHandler(WKNavigationActionPolicyCancel);
    } else {
        decisionHandler(WKNavigationActionPolicyAllow);
    }
}
@end
