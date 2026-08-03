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
