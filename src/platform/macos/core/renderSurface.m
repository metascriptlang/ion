// Ion macOS — render surface: host a native view in a window, composited
// against the WKWebView.
//
// Phase 1: adopt mode + Below z-order. The renderer (e.g. libgodot) creates
// its own NSView; we reparent it into the window's contentView, below the
// webview, and clear the webview's background so the surface shows through.
// Mode B (Ion-owned CAMetalLayer) and a native CVDisplayLink frame clock are
// later phases — see docs/RENDER-SURFACE.md.
//
// Surfaces live in a small self-contained table here, keyed by an opaque
// IonRenderSurfaceId (the slot index). Each record points back at its window
// by IonWindowId; the per-window NSWindow/webview are looked up on demand via
// ionMacWindowState, so a surface never holds a stale window handle.

#import "../state.h"
#import "../../bridge.h"
#import <QuartzCore/QuartzCore.h>

#include "../../common/windowRegistry.h"
#include "../../common/inputEvents.h"

#define ION_MAX_SURFACES 16

// When set, the host view injects mouse events straight into the renderer
// (low latency); otherwise it enqueues them for ionPollEvent (return 4).
static IonInputSink s_input_sink = NULL;

void ionRenderSurfaceSetInputSink(IonInputSink sink) { s_input_sink = sink; }

static void ionSurfaceDispatch(int type, double x, double y, double p1, double p2) {
    if (s_input_sink) s_input_sink(type, x, y, p1, p2);
    else ion_input_push(type, x, y, p1, p2);
}

// The surface host view. When the surface is on top (INPUT_FULL) it is the
// hit-test target, so it reliably receives mouse events — which it converts to
// top-left window pixels and dispatches into the renderer. (SDL's content view
// sits below the webview, so polling SDL for mouse input is unreliable once a
// surface overlays it.)
@interface IonSurfaceView : NSView
@end

@implementation IonSurfaceView

- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }

- (void)updateTrackingAreas {
    for (NSTrackingArea *ta in [self.trackingAreas copy]) [self removeTrackingArea:ta];
    NSTrackingArea *area = [[NSTrackingArea alloc]
        initWithRect:self.bounds
             options:(NSTrackingMouseMoved | NSTrackingActiveAlways | NSTrackingInVisibleRect)
               owner:self
            userInfo:nil];
    [self addTrackingArea:area];
    [super updateTrackingAreas];
}

// Coordinates leave as a FRACTION (0..1) of the surface, origin top-left — the
// renderer scales by its own resolution. This sidesteps the points-vs-pixels /
// Cocoa-backingScale vs SDL-pixel-density mismatch (which broke after resize).
- (void)pushButton:(NSEvent *)event pressed:(int)pressed {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    if (w <= 0 || h <= 0) return;
    ionSurfaceDispatch(1, p.x / w, (h - p.y) / h,
                       (double)(event.buttonNumber + 1), (double)pressed);
}

- (void)pushMotion:(NSEvent *)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    if (w <= 0 || h <= 0) return;
    ionSurfaceDispatch(2, p.x / w, (h - p.y) / h, event.deltaX / w, event.deltaY / h);
}

- (void)mouseDown:(NSEvent *)e        { [self pushButton:e pressed:1]; }
- (void)mouseUp:(NSEvent *)e          { [self pushButton:e pressed:0]; }
- (void)rightMouseDown:(NSEvent *)e   { [self pushButton:e pressed:1]; }
- (void)rightMouseUp:(NSEvent *)e     { [self pushButton:e pressed:0]; }
- (void)otherMouseDown:(NSEvent *)e   { [self pushButton:e pressed:1]; }
- (void)otherMouseUp:(NSEvent *)e     { [self pushButton:e pressed:0]; }
- (void)mouseMoved:(NSEvent *)e       { [self pushMotion:e]; }
- (void)mouseDragged:(NSEvent *)e     { [self pushMotion:e]; }
- (void)rightMouseDragged:(NSEvent *)e { [self pushMotion:e]; }
- (void)otherMouseDragged:(NSEvent *)e { [self pushMotion:e]; }

- (void)scrollWheel:(NSEvent *)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    if (w <= 0 || h <= 0) return;
    ionSurfaceDispatch(3, p.x / w, (h - p.y) / h, event.scrollingDeltaX, event.scrollingDeltaY);
}

@end

typedef struct {
    int          used;
    IonWindowId  win;
    int          z;       // ION_SURFACE_BELOW / ION_SURFACE_ABOVE
    NSView      *view;     // adopted native view (strong under ARC)
} IonMacSurface;

// Zero-initialized static storage — `view` starts nil, so the first ARC
// assignment has no garbage strong ref to release. Same guarantee calloc
// gives IonMacWindowState.
static IonMacSurface s_surfaces[ION_MAX_SURFACES];

static IonMacSurface *surfaceGet(IonRenderSurfaceId surf) {
    if (surf < 0 || surf >= ION_MAX_SURFACES) return NULL;
    IonMacSurface *s = &s_surfaces[surf];
    return s->used ? s : NULL;
}

IonRenderSurfaceId ionRenderSurfaceCreate(IonWindowId win, int z) {
    if (ionMacWindowState(win) == NULL) return ION_RENDER_SURFACE_INVALID;
    for (int i = 0; i < ION_MAX_SURFACES; i++) {
        if (!s_surfaces[i].used) {
            s_surfaces[i].used = 1;
            s_surfaces[i].win  = win;
            s_surfaces[i].z    = z;
            s_surfaces[i].view = nil;
            return (IonRenderSurfaceId)i;
        }
    }
    return ION_RENDER_SURFACE_INVALID;
}

void ionRenderSurfaceAdopt(IonRenderSurfaceId surf, void *nativeView) {
    IonMacSurface *s = surfaceGet(surf);
    if (!s || nativeView == NULL) return;
    IonMacWindowState *st = ionMacWindowState(s->win);
    if (!st || st->nsWindow == nil) return;

    NSView *view    = (__bridge NSView *)nativeView;
    NSView *content = [st->nsWindow contentView];

    view.frame = content.bounds;
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    NSWindowOrderingMode order = (s->z == ION_SURFACE_ABOVE) ? NSWindowAbove : NSWindowBelow;
    [content addSubview:view positioned:order relativeTo:st->webview];

    // For a Below surface the webview must be transparent so the surface shows
    // through. WKWebView exposes no public transparency property; clearing the
    // private drawsBackground is the established mechanism.
    if (s->z == ION_SURFACE_BELOW && st->webview != nil) {
        [st->webview setValue:@NO forKey:@"drawsBackground"];
    }

    s->view = view;
}

void ionRenderSurfaceAdoptLayer(IonRenderSurfaceId surf, long long caLayer) {
    IonMacSurface *s = surfaceGet(surf);
    if (!s || caLayer == 0) return;
    IonMacWindowState *st = ionMacWindowState(s->win);
    if (!st || st->nsWindow == nil) return;
    NSView *content = [st->nsWindow contentView];
    CALayer *layer = (__bridge CALayer *)(void *)(intptr_t)caLayer;

    NSView *hostView = [[IonSurfaceView alloc] initWithFrame:content.bounds];
    hostView.wantsLayer = YES;
    hostView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    layer.frame = hostView.bounds;
    // Live-resize blocks the MS runLoop (syncFrame can't fire until mouse-up),
    // so let the layer scale with the host — stretch-to-fill, not clip mid-drag.
    layer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    layer.contentsGravity = kCAGravityResize;
    // Snap, don't ease: the post-resize reframe must not implicitly animate or
    // the layer rubber-bands on mouse-up.
    layer.actions = @{ @"bounds": [NSNull null], @"position": [NSNull null] };
    [hostView.layer addSublayer:layer];

    NSWindowOrderingMode order = (s->z == ION_SURFACE_ABOVE) ? NSWindowAbove : NSWindowBelow;
    [content addSubview:hostView positioned:order relativeTo:st->webview];

    if (s->z == ION_SURFACE_BELOW && st->webview != nil) {
        [st->webview setValue:@NO forKey:@"drawsBackground"];
    }
    s->view = hostView;
}

void *ionRenderSurfaceLayer(IonRenderSurfaceId surf) {
    (void)surf;
    return NULL;   // Mode B (Ion-owned CAMetalLayer) — Phase 2.
}

void ionRenderSurfaceSetVisible(IonRenderSurfaceId surf, int visible) {
    IonMacSurface *s = surfaceGet(surf);
    if (s && s->view) s->view.hidden = visible ? NO : YES;
}

void ionRenderSurfaceSyncFrame(IonRenderSurfaceId surf) {
    IonMacSurface *s = surfaceGet(surf);
    if (!s || !s->view) return;
    IonMacWindowState *st = ionMacWindowState(s->win);
    if (st && st->nsWindow != nil) {
        s->view.frame = [st->nsWindow contentView].bounds;
    }
    // The hostView autoresizes, but an adopted CALayer (the renderer's, e.g.
    // Godot's CAMetalLayer) does not track its superlayer — reframe it to fill.
    // The renderer still owns its bounds/drawable resolution; this only places
    // the layer so the content covers the resized window.
    CALayer *adopted = s->view.layer.sublayers.firstObject;
    if (adopted != nil) adopted.frame = s->view.bounds;
}

void ionRenderSurfaceSetInputRegion(IonRenderSurfaceId surf,
                                    int mode, int x, int y, int w, int h) {
    (void)x; (void)y; (void)w; (void)h;
    IonMacSurface *s = surfaceGet(surf);
    if (!s || !s->view) return;
    IonMacWindowState *st = ionMacWindowState(s->win);
    if (!st || st->nsWindow == nil || st->webview == nil) return;
    NSView *content = [st->nsWindow contentView];

    // Phase 1: state-driven z-reorder. A transparent WKWebView still hit-tests
    // its whole rect, so the only robust per-state route is which sibling sits
    // on top. FULL → surface above the webview (surface receives input); NONE →
    // surface back at its created z-slot (webview receives input). True RECT
    // clipping needs a window-level event tap — deferred (treated as FULL).
    if (mode == ION_INPUT_NONE) {
        NSWindowOrderingMode order = (s->z == ION_SURFACE_ABOVE) ? NSWindowAbove : NSWindowBelow;
        [content addSubview:s->view positioned:order relativeTo:st->webview];
        [st->nsWindow makeFirstResponder:st->webview];
    } else {
        [content addSubview:s->view positioned:NSWindowAbove relativeTo:st->webview];
        // Without acceptsMouseMovedEvents the window drops mouse-moved events
        // between clicks; without pinning first-responder the webview steals
        // them — together they read as "cursor position lost until next click".
        st->nsWindow.acceptsMouseMovedEvents = YES;
        [st->nsWindow makeFirstResponder:s->view];
        [s->view updateTrackingAreas];
    }
}

void ionRenderSurfaceRelease(IonRenderSurfaceId surf) {
    IonMacSurface *s = surfaceGet(surf);
    if (!s) return;
    if (s->view) {
        // Detach only — the renderer owns the view's lifetime. Dropping our
        // strong ref (nil) lets ARC release Ion's hold; the renderer's own
        // reference keeps it alive.
        [s->view removeFromSuperview];
        s->view = nil;
    }
    s->used = 0;
    s->win  = ION_WINDOW_INVALID;
}
