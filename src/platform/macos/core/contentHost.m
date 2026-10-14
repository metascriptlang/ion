// Pointer button, motion and wheel records come from one process-wide local event monitor
// (the app's views sit above the host and hide those events from it); it returns every
// event unchanged so a webview under the pointer still receives it.


#import "../state.h"
#import "../../bridge.h"
#import "../internal.h"
#include "../../common/inputEvents.h"
#include "../../common/keys.h"
#include "../../common/windowRegistry.h"

#include <string.h>

static void push(int type, IonWindowId win, double x, double y, double p1, double p2) {
    IonInputRecord r;
    memset(&r, 0, sizeof r);
    r.type = type;
    r.window = win;
    r.x = x;
    r.y = y;
    r.p1 = p1;
    r.p2 = p2;
    ion_input_push_record(&r);
}

static void pushText(int type, IonWindowId win, NSString *s, double p1) {
    IonInputRecord r;
    memset(&r, 0, sizeof r);
    r.type = type;
    r.window = win;
    r.p1 = p1;
    r.text = s.UTF8String;
    ion_input_push_record(&r);
}

static int macKeyToIon(unsigned short code) {
    switch (code) {
        case 0x00: return ION_KEY_KEY_A;     case 0x01: return ION_KEY_KEY_S;
        case 0x02: return ION_KEY_KEY_D;     case 0x03: return ION_KEY_KEY_F;
        case 0x04: return ION_KEY_KEY_H;     case 0x05: return ION_KEY_KEY_G;
        case 0x06: return ION_KEY_KEY_Z;     case 0x07: return ION_KEY_KEY_X;
        case 0x08: return ION_KEY_KEY_C;     case 0x09: return ION_KEY_KEY_V;
        case 0x0A: return ION_KEY_INTL_BACKSLASH;
        case 0x0B: return ION_KEY_KEY_B;     case 0x0C: return ION_KEY_KEY_Q;
        case 0x0D: return ION_KEY_KEY_W;     case 0x0E: return ION_KEY_KEY_E;
        case 0x0F: return ION_KEY_KEY_R;     case 0x10: return ION_KEY_KEY_Y;
        case 0x11: return ION_KEY_KEY_T;     case 0x12: return ION_KEY_DIGIT1;
        case 0x13: return ION_KEY_DIGIT2;    case 0x14: return ION_KEY_DIGIT3;
        case 0x15: return ION_KEY_DIGIT4;    case 0x16: return ION_KEY_DIGIT6;
        case 0x17: return ION_KEY_DIGIT5;    case 0x18: return ION_KEY_EQUAL;
        case 0x19: return ION_KEY_DIGIT9;    case 0x1A: return ION_KEY_DIGIT7;
        case 0x1B: return ION_KEY_MINUS;     case 0x1C: return ION_KEY_DIGIT8;
        case 0x1D: return ION_KEY_DIGIT0;    case 0x1E: return ION_KEY_BRACKET_RIGHT;
        case 0x1F: return ION_KEY_KEY_O;     case 0x20: return ION_KEY_KEY_U;
        case 0x21: return ION_KEY_BRACKET_LEFT;
        case 0x22: return ION_KEY_KEY_I;     case 0x23: return ION_KEY_KEY_P;
        case 0x24: return ION_KEY_ENTER;     case 0x25: return ION_KEY_KEY_L;
        case 0x26: return ION_KEY_KEY_J;     case 0x27: return ION_KEY_QUOTE;
        case 0x28: return ION_KEY_KEY_K;     case 0x29: return ION_KEY_SEMICOLON;
        case 0x2A: return ION_KEY_BACKSLASH; case 0x2B: return ION_KEY_COMMA;
        case 0x2C: return ION_KEY_SLASH;     case 0x2D: return ION_KEY_KEY_N;
        case 0x2E: return ION_KEY_KEY_M;     case 0x2F: return ION_KEY_PERIOD;
        case 0x30: return ION_KEY_TAB;       case 0x31: return ION_KEY_SPACE;
        case 0x32: return ION_KEY_BACKQUOTE; case 0x33: return ION_KEY_BACKSPACE;
        case 0x35: return ION_KEY_ESCAPE;
        case 0x36: return ION_KEY_META_RIGHT;    case 0x37: return ION_KEY_META_LEFT;
        case 0x38: return ION_KEY_SHIFT_LEFT;    case 0x39: return ION_KEY_CAPS_LOCK;
        case 0x3A: return ION_KEY_ALT_LEFT;      case 0x3B: return ION_KEY_CONTROL_LEFT;
        case 0x3C: return ION_KEY_SHIFT_RIGHT;   case 0x3D: return ION_KEY_ALT_RIGHT;
        case 0x3E: return ION_KEY_CONTROL_RIGHT; case 0x3F: return ION_KEY_FN;
        case 0x40: return ION_KEY_F17;       case 0x41: return ION_KEY_NUMPAD_DECIMAL;
        case 0x43: return ION_KEY_NUMPAD_MULTIPLY;
        case 0x45: return ION_KEY_NUMPAD_ADD;
        case 0x47: return ION_KEY_NUM_LOCK;
        case 0x4B: return ION_KEY_NUMPAD_DIVIDE;
        case 0x4C: return ION_KEY_NUMPAD_ENTER;
        case 0x4E: return ION_KEY_NUMPAD_SUBTRACT;
        case 0x4F: return ION_KEY_F18;       case 0x50: return ION_KEY_F19;
        case 0x51: return ION_KEY_NUMPAD_EQUAL;
        case 0x52: return ION_KEY_NUMPAD0;   case 0x53: return ION_KEY_NUMPAD1;
        case 0x54: return ION_KEY_NUMPAD2;   case 0x55: return ION_KEY_NUMPAD3;
        case 0x56: return ION_KEY_NUMPAD4;   case 0x57: return ION_KEY_NUMPAD5;
        case 0x58: return ION_KEY_NUMPAD6;   case 0x59: return ION_KEY_NUMPAD7;
        case 0x5A: return ION_KEY_F20;
        case 0x5B: return ION_KEY_NUMPAD8;   case 0x5C: return ION_KEY_NUMPAD9;
        case 0x5D: return ION_KEY_INTL_YEN;  case 0x5E: return ION_KEY_INTL_RO;
        case 0x5F: return ION_KEY_NUMPAD_COMMA;
        case 0x60: return ION_KEY_F5;        case 0x61: return ION_KEY_F6;
        case 0x62: return ION_KEY_F7;        case 0x63: return ION_KEY_F3;
        case 0x64: return ION_KEY_F8;        case 0x65: return ION_KEY_F9;
        case 0x66: return ION_KEY_LANG2;     case 0x67: return ION_KEY_F11;
        case 0x68: return ION_KEY_LANG1;     case 0x69: return ION_KEY_F13;
        case 0x6A: return ION_KEY_F16;       case 0x6B: return ION_KEY_F14;
        case 0x6D: return ION_KEY_F10;       case 0x6F: return ION_KEY_F12;
        case 0x71: return ION_KEY_F15;       case 0x72: return ION_KEY_HELP;
        case 0x73: return ION_KEY_HOME;      case 0x74: return ION_KEY_PAGE_UP;
        case 0x75: return ION_KEY_DELETE;    case 0x76: return ION_KEY_F4;
        case 0x77: return ION_KEY_END;       case 0x78: return ION_KEY_F2;
        case 0x79: return ION_KEY_PAGE_DOWN; case 0x7A: return ION_KEY_F1;
        case 0x7B: return ION_KEY_ARROW_LEFT;  case 0x7C: return ION_KEY_ARROW_RIGHT;
        case 0x7D: return ION_KEY_ARROW_DOWN;  case 0x7E: return ION_KEY_ARROW_UP;
        default: return ION_KEY_UNIDENTIFIED;
    }
}

static NSEventModifierFlags modifierFlagForKey(unsigned short code) {
    switch (code) {
        case 0x36: case 0x37: return NSEventModifierFlagCommand;
        case 0x38: case 0x3C: return NSEventModifierFlagShift;
        case 0x39:            return NSEventModifierFlagCapsLock;
        case 0x3A: case 0x3D: return NSEventModifierFlagOption;
        case 0x3B: case 0x3E: return NSEventModifierFlagControl;
        case 0x3F:            return NSEventModifierFlagFunction;
        default:              return 0;
    }
}

// Device-dependent side bits of NSEvent.modifierFlags (IOKit NX_DEVICER*KEYMASK).
static int modsFromEvent(NSEvent *e) {
    NSEventModifierFlags f = e.modifierFlags;
    int m = 0;
    if (f & NSEventModifierFlagShift)    m |= ION_MOD_SHIFT;
    if (f & NSEventModifierFlagControl)  m |= ION_MOD_CTRL;
    if (f & NSEventModifierFlagOption)   m |= ION_MOD_ALT;
    if (f & NSEventModifierFlagCommand)  m |= ION_MOD_SUPER;
    if (f & NSEventModifierFlagCapsLock) m |= ION_MOD_CAPS_LOCK;
    if (f & 0x0004) m |= ION_MOD_SHIFT_RIGHT;
    if (f & 0x2000) m |= ION_MOD_CTRL_RIGHT;
    if (f & 0x0040) m |= ION_MOD_ALT_RIGHT;
    if (f & 0x0010) m |= ION_MOD_SUPER_RIGHT;
    return m;
}

static BOOL isTypedText(NSString *s) {
    if (s.length == 0) return NO;
    unichar c = [s characterAtIndex:0];
    return c >= 0x20 && c != 0x7F && !(c >= 0xF700 && c <= 0xF8FF);
}

static id     s_monitor = nil;
static int    s_buttonsDown = 0;
static IonWindowId s_lastWin = ION_WINDOW_INVALID;
static double s_lastX, s_lastY;

static IonWindowId windowIdForNSWindow(NSWindow *w) {
    for (IonWindowId i = ion_registry_next(ION_WINDOW_INVALID);
         i != ION_WINDOW_INVALID;
         i = ion_registry_next(i)) {
        IonMacWindowState *st = ionMacWindowState(i);
        if (st && st->nsWindow == w) return i;
    }
    return ION_WINDOW_INVALID;
}

static void handlePointer(NSEvent *e) {
    IonWindowId win = windowIdForNSWindow(e.window);
    if (win == ION_WINDOW_INVALID) return;
    NSView *content = e.window.contentView;
    NSPoint p = [content convertPoint:e.locationInWindow fromView:nil];
    double scale = e.window.backingScaleFactor;
    double px = p.x * scale;
    double py = (content.isFlipped ? p.y : content.bounds.size.height - p.y) * scale;
    BOOL inside = NSPointInRect(p, content.bounds);

    switch (e.type) {
        case NSEventTypeLeftMouseDown:
        case NSEventTypeRightMouseDown:
        case NSEventTypeOtherMouseDown: {
            int b = (int)e.buttonNumber + 1;
            if (!inside || b > 5) return;
            s_buttonsDown |= 1 << b;
            push(ION_INPUT_BUTTON, win, px, py, b, 1);
            break;
        }
        case NSEventTypeLeftMouseUp:
        case NSEventTypeRightMouseUp:
        case NSEventTypeOtherMouseUp: {
            int b = (int)e.buttonNumber + 1;
            if (b > 5 || !(s_buttonsDown & (1 << b))) return;
            s_buttonsDown &= ~(1 << b);
            push(ION_INPUT_BUTTON, win, px, py, b, 0);
            break;
        }
        case NSEventTypeMouseMoved:
        case NSEventTypeLeftMouseDragged:
        case NSEventTypeRightMouseDragged:
        case NSEventTypeOtherMouseDragged: {
            if (!inside && !s_buttonsDown) return;
            BOOL known = s_lastWin == win;
            push(ION_INPUT_MOTION, win, px, py, known ? px - s_lastX : 0, known ? py - s_lastY : 0);
            s_lastWin = win;
            s_lastX = px;
            s_lastY = py;
            break;
        }
        case NSEventTypeScrollWheel: {
            if (!inside) return;
            double k = e.hasPreciseScrollingDeltas ? 0.1 : 1.0;
            push(ION_INPUT_WHEEL, win, px, py, e.scrollingDeltaX * k, e.scrollingDeltaY * k);
            break;
        }
        default:
            break;
    }
}

static void installPointerMonitor(void) {
    if (s_monitor != nil) return;
    NSEventMask mask = NSEventMaskLeftMouseDown | NSEventMaskLeftMouseUp
        | NSEventMaskRightMouseDown | NSEventMaskRightMouseUp
        | NSEventMaskOtherMouseDown | NSEventMaskOtherMouseUp
        | NSEventMaskMouseMoved | NSEventMaskLeftMouseDragged
        | NSEventMaskRightMouseDragged | NSEventMaskOtherMouseDragged
        | NSEventMaskScrollWheel;
    s_monitor = [NSEvent addLocalMonitorForEventsMatchingMask:mask
                                                      handler:^NSEvent *(NSEvent *e) {
        handlePointer(e);
        return e;
    }];
}

@interface IonContentHost : NSView <NSTextInputClient>
@property (nonatomic) IonWindowId win;
@property (nonatomic) int cursorKind;
@property (nonatomic) NSRect imeRectPx;
@property (nonatomic, copy) NSString *marked;
@property (nonatomic) NSMutableArray<NSString *> *commits;
- (void)pushResize;
- (void)pushFocus;
@end

@implementation IonContentHost

- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }

- (BOOL)becomeFirstResponder {
    [self pushFocus];
    return YES;
}

- (BOOL)resignFirstResponder {
    push(ION_INPUT_FOCUS, self.win, 0, 0, 0, 0);
    return YES;
}

- (void)pushFocus {
    BOOL has = self.window.isKeyWindow && self.window.firstResponder == self;
    push(ION_INPUT_FOCUS, self.win, 0, 0, has ? 1 : 0, 0);
}

- (void)pushResize {
    double scale = self.window.backingScaleFactor;
    push(ION_INPUT_RESIZE, self.win, scale, 0,
         self.bounds.size.width * scale, self.bounds.size.height * scale);
}

- (void)setFrameSize:(NSSize)size {
    [super setFrameSize:size];
    [self pushResize];
}

- (void)viewDidChangeBackingProperties {
    [super viewDidChangeBackingProperties];
    [self pushResize];
}

- (void)updateTrackingAreas {
    for (NSTrackingArea *ta in [self.trackingAreas copy]) [self removeTrackingArea:ta];
    [self addTrackingArea:[[NSTrackingArea alloc]
        initWithRect:self.bounds
             options:(NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect)
               owner:self
            userInfo:nil]];
    [super updateTrackingAreas];
}

- (void)mouseExited:(NSEvent *)event {
    s_lastWin = ION_WINDOW_INVALID;
    push(ION_INPUT_LEAVE, self.win, 0, 0, 0, 0);
}

- (void)resetCursorRects {
    NSCursor *c = [NSCursor arrowCursor];
    switch (self.cursorKind) {
        case ION_CURSOR_HAND:     c = [NSCursor pointingHandCursor]; break;
        case ION_CURSOR_IBEAM:    c = [NSCursor IBeamCursor]; break;
        case ION_CURSOR_CROSS:    c = [NSCursor crosshairCursor]; break;
        case ION_CURSOR_RESIZE_H: c = [NSCursor resizeLeftRightCursor]; break;
        case ION_CURSOR_RESIZE_V: c = [NSCursor resizeUpDownCursor]; break;
        default: break;
    }
    [self addCursorRect:self.bounds cursor:c];
}

- (void)keyDown:(NSEvent *)event {
    self.commits = [NSMutableArray array];
    [self interpretKeyEvents:@[event]];
    NSArray<NSString *> *commits = self.commits;
    self.commits = nil;

    NSString *typed = nil;
    NSArray<NSString *> *rest = commits;
    if (commits.count == 1 && isTypedText(event.characters)
        && [commits[0] isEqualToString:event.characters]) {
        typed = commits[0];
        rest = @[];
    }

    IonInputRecord r;
    memset(&r, 0, sizeof r);
    r.type = ION_INPUT_KEY;
    r.window = self.win;
    r.p1 = event.isARepeat ? ION_KEY_REPEAT : ION_KEY_PRESS;
    r.key = macKeyToIon(event.keyCode);
    r.scancode = event.keyCode;
    r.mods = modsFromEvent(event);
    if (typed) {
        if (r.mods & ION_MOD_SHIFT) r.consumedMods |= ION_MOD_SHIFT;
        if (r.mods & ION_MOD_ALT)   r.consumedMods |= ION_MOD_ALT;
    }
    NSString *bare = [event charactersByApplyingModifiers:0];
    r.unshifted = isTypedText(bare) ? [bare characterAtIndex:0] : 0;
    r.text = typed.UTF8String;
    ion_input_push_record(&r);

    for (NSString *s in rest) pushText(ION_INPUT_TEXT, self.win, s, 0);
}

- (void)keyUp:(NSEvent *)event {
    IonInputRecord r;
    memset(&r, 0, sizeof r);
    r.type = ION_INPUT_KEY;
    r.window = self.win;
    r.p1 = ION_KEY_RELEASE;
    r.key = macKeyToIon(event.keyCode);
    r.scancode = event.keyCode;
    r.mods = modsFromEvent(event);
    ion_input_push_record(&r);
}

- (void)flagsChanged:(NSEvent *)event {
    NSEventModifierFlags flag = modifierFlagForKey(event.keyCode);
    if (flag == 0) return;
    IonInputRecord r;
    memset(&r, 0, sizeof r);
    r.type = ION_INPUT_KEY;
    r.window = self.win;
    r.p1 = (event.modifierFlags & flag) ? ION_KEY_PRESS : ION_KEY_RELEASE;
    r.key = macKeyToIon(event.keyCode);
    r.scancode = event.keyCode;
    r.mods = modsFromEvent(event);
    ion_input_push_record(&r);
}

- (void)doCommandBySelector:(SEL)selector {}

- (void)insertText:(id)string replacementRange:(NSRange)range {
    NSString *s = [string isKindOfClass:[NSAttributedString class]]
        ? [(NSAttributedString *)string string] : (NSString *)string;
    [self unmarkText];
    if (self.commits != nil) [self.commits addObject:s];
    else pushText(ION_INPUT_TEXT, self.win, s, 0);
}

- (void)setMarkedText:(id)string selectedRange:(NSRange)selected replacementRange:(NSRange)range {
    NSString *s = [string isKindOfClass:[NSAttributedString class]]
        ? [(NSAttributedString *)string string] : (NSString *)string;
    self.marked = s;
    NSUInteger loc = MIN(selected.location == NSNotFound ? s.length : selected.location, s.length);
    pushText(ION_INPUT_PREEDIT, self.win, s,
             (double)[[s substringToIndex:loc] lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
}

- (void)unmarkText {
    if (self.marked.length == 0) return;
    self.marked = nil;
    pushText(ION_INPUT_PREEDIT, self.win, @"", 0);
}

- (BOOL)hasMarkedText { return self.marked.length > 0; }
- (NSRange)markedRange { return self.marked.length > 0 ? NSMakeRange(0, self.marked.length) : NSMakeRange(NSNotFound, 0); }
- (NSRange)selectedRange { return NSMakeRange(NSNotFound, 0); }
- (NSArray<NSAttributedStringKey> *)validAttributesForMarkedText { return @[]; }
- (NSAttributedString *)attributedSubstringForProposedRange:(NSRange)range actualRange:(NSRangePointer)actual { return nil; }
- (NSUInteger)characterIndexForPoint:(NSPoint)point { return NSNotFound; }

- (NSRect)firstRectForCharacterRange:(NSRange)range actualRange:(NSRangePointer)actual {
    double scale = self.window.backingScaleFactor;
    NSRect px = self.imeRectPx;
    NSRect inView = NSMakeRect(px.origin.x / scale,
                               self.bounds.size.height - (px.origin.y + px.size.height) / scale,
                               px.size.width / scale, px.size.height / scale);
    return [self.window convertRectToScreen:[self convertRect:inView toView:nil]];
}

@end

NSView *ionContentHostCreate(IonWindowId winId, NSWindow *nsWindow) {
    installPointerMonitor();
    NSView *content = nsWindow.contentView;
    IonContentHost *host = [[IonContentHost alloc] initWithFrame:content.bounds];
    host.win = winId;
    host.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [content addSubview:host positioned:NSWindowBelow relativeTo:nil];
    [nsWindow makeFirstResponder:host];

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    NSOperationQueue *main = [NSOperationQueue mainQueue];
    __weak IonContentHost *weak = host;
    void (^refocus)(NSNotification *) = ^(NSNotification *n) { [weak pushFocus]; };
    [nc addObserverForName:NSWindowDidBecomeKeyNotification object:nsWindow queue:main usingBlock:refocus];
    [nc addObserverForName:NSWindowDidResignKeyNotification object:nsWindow queue:main usingBlock:refocus];

    [host pushResize];
    return host;
}

void ionContentHostDestroy(NSView *host) {
    [host removeFromSuperview];
}

void ionContentHostSetCursor(NSView *host, int cursor) {
    IonContentHost *h = (IonContentHost *)host;
    h.cursorKind = cursor;
    [h.window invalidateCursorRectsForView:h];
}

void ionContentHostSetImeRect(NSView *host, int x, int y, int w, int h) {
    ((IonContentHost *)host).imeRectPx = NSMakeRect(x, y, w, h);
}
