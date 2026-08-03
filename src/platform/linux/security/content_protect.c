// Ion Linux — content protection (screen-capture suppression).
//
// Linux has no portable equivalent to NSWindow.sharingType or
// SetWindowDisplayAffinity. Some Wayland compositors offer per-surface
// content-type hints (KDE's KWin, GNOME's Mutter w/ extension), but X11
// fundamentally exposes all window contents to any X client. Until a
// portable story emerges (Wayland-only future), this is a no-op stub.

#include "../../bridge.h"

#include <stdio.h>

void ionSetContentProtected(int on) {
    if (on) {
        fprintf(stderr, "[ion] setContentProtected: not supported on Linux (Phase 1)\n");
    }
}
