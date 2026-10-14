
#import "../state.h"
#import "../../bridge.h"
#import "../internal.h"
#include "../../common/protoReg.h"
#include "../../common/webviewRegistry.h"

#include <stdlib.h>

IonWebviewId ionWebviewCreate(IonWindowId win, const char *label, const char *url) {
    if (ionMacWindowState(win) == NULL) return ION_WEBVIEW_INVALID;
    IonWebviewId wvId = ion_webview_alloc(label, win);
    if (wvId == ION_WEBVIEW_INVALID) return ION_WEBVIEW_INVALID;

    ionProtoFreeze();

    IonMacWebviewState *st = (IonMacWebviewState *)calloc(1, sizeof(IonMacWebviewState));
    if (!st) {
        ion_webview_free(wvId);
        return ION_WEBVIEW_INVALID;
    }
    id delegate = nil;
    st->view = ionSetupWebview(label, wvId, &delegate);
    st->navDelegate = delegate;
    ion_webview_get(wvId)->platformState = st;

    ionWebviewNavigate(wvId, url);
    return wvId;
}

void ionWebviewRelease(IonWebviewId id) {
    IonMacWebviewState *st = ionMacWebviewState(id);
    if (!st) return;
    st->view.navigationDelegate = nil;
    [st->view.configuration.userContentController removeScriptMessageHandlerForName:@"ion"];
    [st->view removeFromSuperview];
    st->view = nil;
    st->navDelegate = nil;
    free(st);
    ion_webview_free(id);
}

void *ionWebviewNode(IonWebviewId id) {
    IonMacWebviewState *st = ionMacWebviewState(id);
    return st ? (__bridge void *)st->view : NULL;
}

// Assumes the app parents the node directly in ionWindowRoot: the rect is set in the
// superview's coordinates, flipped against its height unless it is flipped.
void ionWebviewSetBounds(IonWebviewId id, int x, int y, int w, int h) {
    IonMacWebviewState *st = ionMacWebviewState(id);
    IonMacWindowState *win = ionMacWindowState(ionWebviewWindow(id));
    if (!st || !win || win->nsWindow == nil) return;
    double scale = win->nsWindow.backingScaleFactor;
    NSView *parent = st->view.superview ?: win->nsWindow.contentView;
    double px = x / scale, pw = w / scale, ph = h / scale;
    double py = parent.isFlipped ? y / scale
                                 : parent.bounds.size.height - (y + h) / scale;
    st->view.frame = NSMakeRect(px, py, pw, ph);
}

void ionWebviewSetVisible(IonWebviewId id, int visible) {
    IonMacWebviewState *st = ionMacWebviewState(id);
    if (st) st->view.hidden = visible ? NO : YES;
}

// WKWebView has no public transparency property; the private drawsBackground key is the
// established mechanism.
void ionWebviewSetTransparent(IonWebviewId id, int transparent) {
    IonMacWebviewState *st = ionMacWebviewState(id);
    if (st) [st->view setValue:(transparent ? @NO : @YES) forKey:@"drawsBackground"];
}

void ionWebviewFocus(IonWebviewId id) {
    IonMacWebviewState *st = ionMacWebviewState(id);
    IonMacWindowState *win = ionMacWindowState(ionWebviewWindow(id));
    if (st && win && win->nsWindow) [win->nsWindow makeFirstResponder:st->view];
}

// The WKWebView is a real NSView that receives OS pointer events itself: nothing to forward.
void ionWebviewForwardPointer(IonWebviewId id, int kind, double x, double y,
                              int button, double delta) {
    (void)id; (void)kind; (void)x; (void)y; (void)button; (void)delta;
}
