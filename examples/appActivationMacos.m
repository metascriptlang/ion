#import <Cocoa/Cocoa.h>
#include "appActivationMacos.h"

void aaActivateSelf(void) { [NSApp activateIgnoringOtherApps:YES]; }
void aaActivateFinder(void) {
    [[NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.finder"].firstObject activateWithOptions:0];
}
void aaHide(void) { [NSApp hide:nil]; }
void aaUnhide(void) { [NSApp unhide:nil]; }
