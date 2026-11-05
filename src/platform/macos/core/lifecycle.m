// Ion macOS — process lifecycle: SDL init/quit + URL handler install.

#import "../state.h"
#import "../../bridge.h"
#import "../internal.h"

int ionInit(void) {
    int ok = SDL_Init(SDL_INIT_VIDEO) ? 1 : 0;
    // Install AFTER SDL_Init so SDL's NSApp delegate setup doesn't override us.
    // Cold-start URLs survive: the kAEGetURL AppleEvent sits in the queue until
    // the first SDL_WaitEventTimeout pumps the Cocoa run loop, by which time
    // our handler is registered.
    ionInstallURLHandler();
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    NSDictionary<NSNotificationName, NSString *> *messages = @{
        NSApplicationDidBecomeActiveNotification: @"app.active",
        NSApplicationDidResignActiveNotification: @"app.inactive",
        NSApplicationDidHideNotification: @"app.hidden",
        NSApplicationDidUnhideNotification: @"app.shown",
    };
    for (NSNotificationName name in messages) {
        NSString *message = messages[name];
        [center addObserverForName:name object:NSApp queue:nil usingBlock:^(NSNotification *note) {
            (void)note;
            ionEnqueueMessage(message, @"");
        }];
    }
    return ok;
}

int ionRequestX11(void) {
    return 0;
}

// LaunchServices starts one instance of a bundle and delivers later URLs to it.
int ionRequestSingleInstance(void) {
    return 1;
}

void ionQuit(void) {
    SDL_Quit();
}
