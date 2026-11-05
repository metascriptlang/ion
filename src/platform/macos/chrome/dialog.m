// Ion macOS — native file dialog (NSOpenPanel).
//
// v0: single-file selection only, any file type. Returns the selected path
// or "" if the user cancelled. Blocks the SDL event loop until dismissed.
//
// ionFileOpenWindow takes a window id but currently runs application-modal
// (identical to ionFileOpen). The id is reserved for future window-modal
// sheet behavior via beginSheetModalForWindow.

#import "../../bridge.h"
#import "../internal.h"

static msString runOpenPanel(void) {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    if ([panel runModal] != NSModalResponseOK) return MS_EMPTY_STRING;
    return nsStringToMs(panel.URLs.firstObject.path);
}

msString ionFileOpen(void) {
    return runOpenPanel();
}

msString ionFileOpenWindow(IonWindowId winId) {
    (void)winId;   // reserved — see header
    return runOpenPanel();
}

static NSMutableArray<NSString *> *s_messageButtons = nil;

void ionMessageBoxAddButton(const char *label) {
    if (s_messageButtons == nil) s_messageButtons = [NSMutableArray array];
    [s_messageButtons addObject:[NSString stringWithUTF8String:label] ?: @""];
}

int ionMessageBoxRun(const char *title, const char *message, int style) {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithUTF8String:title] ?: @"";
    alert.informativeText = [NSString stringWithUTF8String:message] ?: @"";
    alert.alertStyle = style == ION_MESSAGE_STYLE_CRITICAL ? NSAlertStyleCritical
                     : style == ION_MESSAGE_STYLE_WARNING ? NSAlertStyleWarning
                     : NSAlertStyleInformational;
    NSUInteger count = s_messageButtons.count;
    for (NSString *label in s_messageButtons) [alert addButtonWithTitle:label];
    s_messageButtons = nil;
    NSModalResponse r = [alert runModal];
    NSInteger index = r - NSAlertFirstButtonReturn;
    return index >= 0 && (NSUInteger)index < count ? (int)index : ION_MESSAGE_BOX_DISMISSED;
}
