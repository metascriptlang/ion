// Ion macOS — deep link URL scheme handler (myapp://… etc.).
//
// Registered via NSAppleEventManager. macOS dispatches kAEGetURL when:
//   - app is launched from `open myapp://…` (cold start)
//   - URL is opened while app is already running (runtime)
//
// Cold-start URLs survive even though the handler is installed AFTER SDL_Init:
// the AppleEvent sits in the event queue until the run loop pumps, and our
// first SDL_WaitEventTimeout pumps it. By then ionInstallURLHandler() has run.

#import "../state.h"
#include "../../common/queue.h"

@interface IonURLHandler : NSObject
- (void)handleURLEvent:(NSAppleEventDescriptor *)event
        withReplyEvent:(NSAppleEventDescriptor *)reply;
@end

@implementation IonURLHandler
- (void)handleURLEvent:(NSAppleEventDescriptor *)event
        withReplyEvent:(NSAppleEventDescriptor *)reply {
    NSString *urlString = [[event paramDescriptorForKeyword:keyDirectObject] stringValue];
    if (urlString == nil) return;
    NSLog(@"[ion] deeplink: %@", urlString);
    ion_queue_push("deeplink", [urlString UTF8String]);
}
@end

static IonURLHandler *s_urlHandler = nil;

void ionInstallURLHandler(void) {
    if (s_urlHandler != nil) return;
    s_urlHandler = [[IonURLHandler alloc] init];
    [[NSAppleEventManager sharedAppleEventManager]
        setEventHandler:s_urlHandler
            andSelector:@selector(handleURLEvent:withReplyEvent:)
          forEventClass:kInternetEventClass
             andEventID:kAEGetURL];
}
