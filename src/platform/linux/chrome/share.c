// Ion Linux — GTK and the desktop portals have no share picker (TODO.md).

#include "../../bridge.h"

int ionShare(const char *title, const char *text, const char *url) {
    (void)title; (void)text; (void)url;
    return ION_SERVICE_UNSUPPORTED;
}
