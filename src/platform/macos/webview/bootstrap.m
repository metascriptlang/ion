// Ion macOS — WKWebView setup + JS bootstrap injection + IPC message handler.
//
// Three things happen in this file:
//   1. WKWebView config — persistent data store, env-gated DevTools.
//   2. Bootstrap JS injected at document start — defines window.ion (frozen
//      object with closure-scoped invoke_key), console.log relay, error
//      forwarders, Promise-style call() with __response routing.
//   3. IonMessageHandler — receives postMessage from JS, validates invoke_key,
//      enqueues onto the IPC queue.
//
// forMainFrameOnly:YES — iframes do NOT get window.ion. Defense-in-depth so
// embedded cross-origin frames can't reach the IPC API.

#import "../state.h"
#import "../internal.h"
#import <WebKit/WebKit.h>
#include "../../common/invokekey.h"
#include "../../common/protocol.h"
#include "../../common/bootstrap.h"

#include <stdlib.h>

// Forward decl — defined in nav_delegate.m.
@interface IonNavigationDelegate : NSObject <WKNavigationDelegate>
@end

// ---- WKScriptMessageHandler ------------------------------------------------

@interface IonMessageHandler : NSObject <WKScriptMessageHandler>
@end

@implementation IonMessageHandler
- (void)userContentController:(WKUserContentController *)ucc
      didReceiveScriptMessage:(WKScriptMessage *)message {
    if (![message.body isKindOfClass:[NSDictionary class]]) return;
    NSDictionary *body = (NSDictionary *)message.body;

    // invoke_key gate: drop messages without the per-launch token.
    // Token lives in a closure inside the bootstrap script — iframes,
    // bookmarklets, content injected outside our bootstrap can't forge it.
    id rawKey = body[@"__key"];  // ION_FIELD_KEY (common/protocol.h)
    const char *candidate = [rawKey isKindOfClass:[NSString class]]
        ? [(NSString *)rawKey UTF8String]
        : NULL;
    if (!ion_invoke_key_verify(candidate)) {
        NSLog(@"[ion] IPC rejected: invalid invoke_key");
        return;
    }

    id rawName = body[@"name"];
    id rawPayload = body[@"payload"];
    if (![rawName isKindOfClass:[NSString class]]) return;
    NSString *name = (NSString *)rawName;
    NSString *payload = [rawPayload isKindOfClass:[NSString class]] ? (NSString *)rawPayload : @"";
    ionEnqueueMessage(name, payload);
}
@end

// ---- Webview factory -------------------------------------------------------

WKWebView *ionSetupWebview(NSView *contentView, const char *windowLabel) {
    WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
    cfg.websiteDataStore = [WKWebsiteDataStore defaultDataStore];

    // DevTools off by default; enable with ION_DEVTOOLS=1.
    const char *envDev = getenv("ION_DEVTOOLS");
    BOOL devtools = (envDev != NULL) &&
        (envDev[0] == '1' ||
         strcasecmp(envDev, "true") == 0 ||
         strcasecmp(envDev, "yes")  == 0 ||
         strcasecmp(envDev, "on")   == 0);
    [cfg.preferences setValue:(devtools ? @YES : @NO) forKey:@"developerExtrasEnabled"];

    WKUserContentController *ucc = cfg.userContentController;

    // Bootstrap = transport ONLY. Public ergonomic API (call/on/off + Promise
    // routing) lives in the @metascriptlang/ion npm package, which the web
    // bundle imports. We only expose the bare minimum needed to talk to native:
    //   window.__ion__.post(name, payload)           — JS → native
    //   window.__ion__.setReceiver(fn)               — npm package registers here
    //   window.__ion__._dispatch(name, payload)      — native → JS (called by ionEvalJS)
    // Plus the auto console-relay so debugging works even before the npm
    // package is loaded.
    //
    // The JS template lives in platform/common/bootstrap.{h,c} so the Windows
    // WebView2 layer can consume the same source. Only the native-post body
    // (WKWebView vs WebView2) differs.
    char *jsBuf = ion_build_bootstrap_js_w(
        ion_invoke_key(),
        windowLabel ? windowLabel : "",
        "window.webkit.messageHandlers.ion.postMessage(envelope);"
    );
    NSString *bootstrap = jsBuf ? [NSString stringWithUTF8String:jsBuf] : @"";
    free(jsBuf);

    WKUserScript *script =
        [[WKUserScript alloc] initWithSource:bootstrap
                               injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                            forMainFrameOnly:YES];
    [ucc addUserScript:script];
    [ucc addScriptMessageHandler:[[IonMessageHandler alloc] init] name:@"ion"];

    // Wire custom URI scheme handlers (ion://, asset://, app-registered).
    // Must run BEFORE WKWebView alloc — setURLSchemeHandler:forURLScheme:
    // throws once the config is in use by a webview.
    ionInstallSchemeHandlers(cfg);

    NSRect frame = contentView.bounds;
    WKWebView *wv = [[WKWebView alloc] initWithFrame:frame configuration:cfg];
    wv.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [contentView addSubview:wv];

    s_navDelegate = [[IonNavigationDelegate alloc] init];
    wv.navigationDelegate = (id<WKNavigationDelegate>)s_navDelegate;

    return wv;
}
