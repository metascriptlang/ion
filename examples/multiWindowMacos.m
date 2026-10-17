#import <Cocoa/Cocoa.h>
#include "multiWindowMacos.h"

void probeUserClose(void *root) {
    [((__bridge NSView *)root).window performClose:nil];
}
