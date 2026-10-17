// Ion macOS — the vsync tick behind the frame clock. One CADisplayLink on the content host of
// the first visible window (Linux ticks the same way, through GTK's frame clock), running only
// while some window is due a frame. Its callback runs on the main run loop while it runs,
// records the time and nudges the wait in ionPollEvent.

#import "../state.h"
#import "../internal.h"
#import <QuartzCore/QuartzCore.h>
#include "../../common/frameClock.h"
#include "../../common/windowRegistry.h"

#include <stdatomic.h>

@interface IonFrameTarget : NSObject
- (void)tick:(CADisplayLink *)link;
@end

static NSView        *s_driver;
static CADisplayLink *s_link;
static IonFrameTarget *s_target;
static atomic_int     s_tickPending;
static double         s_tickMs;

@implementation IonFrameTarget
- (void)tick:(CADisplayLink *)link {
    s_tickMs = link.timestamp * 1000.0;
    if (atomic_exchange(&s_tickPending, 1)) return;
    ionMacNudge();
}
@end

static NSView *firstVisible(void) {
    for (IonWindowId i = ion_registry_next(ION_WINDOW_INVALID);
         i != ION_WINDOW_INVALID;
         i = ion_registry_next(i)) {
        IonMacWindowState *st = ionMacWindowState(i);
        if (!st || !st->sdlWindow) continue;
        SDL_WindowFlags f = SDL_GetWindowFlags(st->sdlWindow);
        if (!(f & (SDL_WINDOW_HIDDEN | SDL_WINDOW_MINIMIZED | SDL_WINDOW_OCCLUDED))) return st->host;
    }
    return nil;
}

static void stopTick(void) {
    [s_link invalidate];
    s_link = nil;
    s_driver = nil;
}

void ionMacFrameSync(void) {
    NSView *want = ion_frame_wanted() ? firstVisible() : nil;
    if (want == s_driver) return;
    stopTick();
    if (want == nil) return;
    if (s_target == nil) s_target = [IonFrameTarget new];
    s_driver = want;
    s_link = [want displayLinkWithTarget:s_target selector:@selector(tick:)];
    [s_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

void ionMacFrameDetach(NSView *host) {
    if (host == s_driver) stopTick();
}

int ionMacFrameTickPending(void) {
    return atomic_load(&s_tickPending);
}

int ionMacFrameTakeTick(double *timeMs) {
    if (!atomic_exchange(&s_tickPending, 0)) return 0;
    *timeMs = s_tickMs;
    return 1;
}
