// Ion macOS — text clipboard (NSPasteboard, general pasteboard).

#import "../../bridge.h"
#import "../internal.h"

msString ionClipboardRead(void) {
    NSString *text = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString];
    return text == nil ? MS_EMPTY_STRING : nsStringToMs(text);
}

int ionClipboardWrite(const char *text) {
    NSPasteboard *board = [NSPasteboard generalPasteboard];
    [board clearContents];
    return [board setString:@(text != NULL ? text : "") forType:NSPasteboardTypeString] ? 1 : 0;
}
