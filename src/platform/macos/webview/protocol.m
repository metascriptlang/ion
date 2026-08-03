// Ion macOS — WKURLSchemeHandler implementation.
//
// WebKit invokes startURLSchemeTask: for every `<scheme>://...` request that
// matches a scheme registered via [config setURLSchemeHandler:forURLScheme:]
// in bootstrap.m. This handler routes through the cross-platform protoreg
// lookup (src/platform/common/protoreg.c) — same logic mac + win + linux.
//
// Threading: WebKit fires these callbacks on its main thread. The protoreg
// registry is frozen at ionOpen() time, so reads are safe without locking.

#import <WebKit/WebKit.h>
#include "../../common/protoReg.h"
#include <stdlib.h>

@interface IonProtocolHandler : NSObject <WKURLSchemeHandler>
@end

@implementation IonProtocolHandler

- (void)webView:(WKWebView *)webView startURLSchemeTask:(id<WKURLSchemeTask>)task {
    NSURL *url = task.request.URL;
    const char *scheme = url.scheme.lowercaseString.UTF8String;
    NSString *nspath = url.path;
    if (nspath == nil) nspath = @"/";
    const char *rawPath = [nspath UTF8String];

    unsigned char *body = NULL;
    size_t len = 0;
    const char *mime = NULL;
    int status = 200;

    IonProtoStatus lr = ionProtoLookup(scheme, rawPath, &body, &len, &mime, &status);

    if (lr == IonProtoNoScheme) {
        // Shouldn't happen — WebKit only fires for registered schemes — but be
        // defensive: respond with 404 instead of dangling the task.
        status = 404;
        mime = "text/plain; charset=utf-8";
    }

    NSDictionary *headers = @{
        @"Content-Type": [NSString stringWithUTF8String:(mime ? mime : "application/octet-stream")],
        @"Content-Length": [NSString stringWithFormat:@"%lu", (unsigned long)len],
        // Pages served via custom scheme inherit origin <scheme>://localhost.
        // Permissive CORS for own-scheme requests so fetch() works the same as
        // a normal HTTPS origin.
        @"Access-Control-Allow-Origin": @"*",
    };

    NSHTTPURLResponse *resp =
        [[NSHTTPURLResponse alloc] initWithURL:url
                                    statusCode:status
                                   HTTPVersion:@"HTTP/1.1"
                                  headerFields:headers];
    [task didReceiveResponse:resp];

    if (body != NULL && len > 0) {
        NSData *data = [NSData dataWithBytes:body length:len];
        [task didReceiveData:data];
    }
    if (body) free(body);

    [task didFinish];
}

- (void)webView:(WKWebView *)webView stopURLSchemeTask:(id<WKURLSchemeTask>)task {
    // No-op — we don't hold per-task state; sync read completes before stop
    // can race in. Required to satisfy the protocol.
    (void)webView; (void)task;
}

@end

// ---- C entry point — bootstrap.m calls this before WKWebView init --------

void ionInstallSchemeHandlers(WKWebViewConfiguration *cfg) {
    if (cfg == nil) return;
    int n = ionProtoSchemeCount();
    if (n <= 0) return;

    static IonProtocolHandler *sHandler = nil;
    if (sHandler == nil) sHandler = [[IonProtocolHandler alloc] init];

    for (int i = 0; i < n; i++) {
        const char *scheme = ionProtoSchemeAt(i);
        if (scheme == NULL || scheme[0] == 0) continue;
        NSString *ns = [NSString stringWithUTF8String:scheme];
        [cfg setURLSchemeHandler:sHandler forURLScheme:ns];
    }
}
