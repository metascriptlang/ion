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
    return ok;
}

void ionQuit(void) {
    SDL_Quit();
}
