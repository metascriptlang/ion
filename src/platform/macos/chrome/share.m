// Ion macOS — share picker (NSSharingServicePicker) anchored to the key window.

#import <Cocoa/Cocoa.h>
#include "../../bridge.h"

@interface IonSharePicker : NSObject <NSSharingServicePickerDelegate, NSSharingServiceDelegate>
@property(nonatomic, copy) NSString *subject;
@property(nonatomic, strong) NSSharingServicePicker *picker;
@end

@implementation IonSharePicker
- (id<NSSharingServiceDelegate>)sharingServicePicker:(NSSharingServicePicker *)picker
                           delegateForSharingService:(NSSharingService *)service {
    (void)picker;
    if (self.subject.length > 0) service.subject = self.subject;
    return nil;
}
@end

static IonSharePicker *s_share = nil;

int ionShare(const char *title, const char *text, const char *url) {
    NSView *anchor = NSApp.keyWindow.contentView ?: NSApp.mainWindow.contentView;
    if (anchor == nil) return ION_SERVICE_NO_WINDOW;
    NSMutableArray *items = [NSMutableArray array];
    NSString *t = [NSString stringWithUTF8String:text];
    if (t.length > 0) [items addObject:t];
    NSString *u = [NSString stringWithUTF8String:url];
    NSURL *link = u.length > 0 ? [NSURL URLWithString:u] : nil;
    if (link != nil) [items addObject:link];
    if (items.count == 0) return ION_SERVICE_REFUSED;

    s_share = [[IonSharePicker alloc] init];
    s_share.subject = [NSString stringWithUTF8String:title];
    s_share.picker = [[NSSharingServicePicker alloc] initWithItems:items];
    s_share.picker.delegate = s_share;
    NSRect b = anchor.bounds;
    NSRect top = NSMakeRect(NSMidX(b) - 1, anchor.isFlipped ? NSMinY(b) : NSMaxY(b) - 1, 2, 1);
    [s_share.picker showRelativeToRect:top ofView:anchor preferredEdge:NSRectEdgeMinY];
    return ION_SERVICE_DONE;
}
