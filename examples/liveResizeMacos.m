#import <Cocoa/Cocoa.h>
#include "liveResizeMacos.h"

#include <stdatomic.h>
#include <stdio.h>
#include <unistd.h>

#define SCENARIO_MS 2000
#define DRAG_STEPS 100
#define MIN_RATE_OF_CONTROL 0.25

enum { KindFrame, KindTimer, KindResize, KindCount };

static NSWindow *s_window;
static atomic_long s_count[KindCount];
static long s_startSnap[KindCount];
static long s_endSnap[KindCount];
static double s_startMs, s_endMs;
static atomic_int s_started, s_ended, s_done, s_failures;
static double s_controlRate[KindCount];

static double nowMs(void) { return NSProcessInfo.processInfo.systemUptime * 1000.0; }

static void snapshot(long *into) {
    for (int k = 0; k < KindCount; k++) into[k] = atomic_load(&s_count[k]);
}

void lrBind(void *root) {
    s_window = ((__bridge NSView *)root).window;
    NSNotificationCenter *c = NSNotificationCenter.defaultCenter;
    [c addObserverForName:NSWindowWillStartLiveResizeNotification object:s_window queue:nil
               usingBlock:^(NSNotification *n) {
        (void)n;
        snapshot(s_startSnap);
        s_startMs = nowMs();
        atomic_store(&s_started, 1);
    }];
    [c addObserverForName:NSWindowDidEndLiveResizeNotification object:s_window queue:nil
               usingBlock:^(NSNotification *n) {
        (void)n;
        snapshot(s_endSnap);
        s_endMs = nowMs();
        atomic_store(&s_ended, 1);
    }];
}

void lrCount(int kind) { atomic_fetch_add(&s_count[kind], 1); }

static void line(const char *name, double ms, const long *a, const long *b, int control) {
    printf("%s window=%.1fms frames=%ld interval10ms=%ld resized=%ld\n", name, ms,
           b[KindFrame] - a[KindFrame], b[KindTimer] - a[KindTimer], b[KindResize] - a[KindResize]);
    if (control) {
        for (int k = 0; k < KindCount; k++) s_controlRate[k] = (double)(b[k] - a[k]) / ms;
    } else {
        int ok = 1;
        for (int k = KindFrame; k <= KindTimer; k++) {
            double rate = (double)(b[k] - a[k]) / ms;
            if (rate <= 0 || rate < MIN_RATE_OF_CONTROL * s_controlRate[k]) ok = 0;
        }
        if (b[KindResize] - a[KindResize] <= 0) ok = 0;
        if (!ok) atomic_fetch_add(&s_failures, 1);
        printf("liveResizeMacos %s: %s\n", ok ? "PASS" : "FAIL", name);
    }
    fflush(stdout);
}

static NSEvent *mouse(NSEventType type, NSPoint inWindow) {
    return [NSEvent mouseEventWithType:type location:inWindow modifierFlags:0
                             timestamp:NSProcessInfo.processInfo.systemUptime
                          windowNumber:s_window.windowNumber context:nil eventNumber:0
                            clickCount:1 pressure:type == NSEventTypeLeftMouseUp ? 0.0f : 1.0f];
}

static void post(NSEvent *ev) { [NSApp postEvent:ev atStart:NO]; }

static void drag(void) {
    __block NSPoint corner;
    dispatch_sync(dispatch_get_main_queue(), ^{
        [NSApp activateIgnoringOtherApps:YES];
        [s_window makeKeyAndOrderFront:nil];
        corner = NSMakePoint(s_window.frame.size.width - 1, 1);
    });
    atomic_store(&s_started, 0);
    atomic_store(&s_ended, 0);
    post(mouse(NSEventTypeLeftMouseDown, corner));
    for (int i = 1; i <= DRAG_STEPS; i++) {
        usleep(SCENARIO_MS * 1000 / DRAG_STEPS);
        post(mouse(NSEventTypeLeftMouseDragged, NSMakePoint(corner.x + i * 2, corner.y - i)));
    }
    post(mouse(NSEventTypeLeftMouseUp, NSMakePoint(corner.x + DRAG_STEPS * 2, corner.y - DRAG_STEPS)));
    for (int i = 0; i < 100 && !atomic_load(&s_ended); i++) usleep(10000);
    const char *name = "live resize (corner drag)";
    if (!atomic_load(&s_started)) {
        printf("%s: AppKit started no live resize from the posted drag\n", name);
        printf("liveResizeMacos FAIL: %s\n", name);
        atomic_fetch_add(&s_failures, 1);
    } else if (!atomic_load(&s_ended)) {
        printf("%s: no live-resize end within 1 s of the posted mouse-up\n", name);
        printf("liveResizeMacos FAIL: %s\n", name);
        atomic_fetch_add(&s_failures, 1);
    } else {
        line(name, s_endMs - s_startMs, s_startSnap, s_endSnap, 0);
    }
}

void lrRun(int scenario) {
    atomic_store(&s_done, 0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        if (scenario == 0) {
            long a[KindCount], b[KindCount];
            snapshot(a);
            double t0 = nowMs();
            usleep(SCENARIO_MS * 1000);
            snapshot(b);
            line("control                  ", nowMs() - t0, a, b, 1);
        } else {
            drag();
        }
        fflush(stdout);
        atomic_store(&s_done, 1);
    });
}

int lrDone(void) { return atomic_load(&s_done); }
int lrFailures(void) { return atomic_load(&s_failures); }
