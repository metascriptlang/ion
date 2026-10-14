#include "frameClock.h"
#include "inputEvents.h"
#include "../bridge.h"

#include <string.h>

typedef struct {
    int open;
    int active;
    int visible;
    int policy;
    int whenInactive;
    int requested;
} IonFrameWindow;

static IonFrameWindow s_windows[ION_MAX_WINDOWS];

static IonFrameWindow *windowAt(int win) {
    if (win < 0 || win >= ION_MAX_WINDOWS || !s_windows[win].open) return NULL;
    return &s_windows[win];
}

static int due(const IonFrameWindow *w) {
    if (!w->visible) return 0;
    if (w->requested) return 1;
    return w->policy == ION_FRAME_CONTINUOUS && (w->active || w->whenInactive);
}

void ion_frame_window_open(int win) {
    if (win < 0 || win >= ION_MAX_WINDOWS) return;
    memset(&s_windows[win], 0, sizeof s_windows[win]);
    s_windows[win].open = 1;
    s_windows[win].active = 1;
    s_windows[win].visible = 1;
    s_windows[win].policy = ION_FRAME_ON_DEMAND;
}

void ion_frame_window_close(int win) {
    if (win < 0 || win >= ION_MAX_WINDOWS) return;
    memset(&s_windows[win], 0, sizeof s_windows[win]);
}

void ion_frame_window_state(int win, int active, int visible) {
    IonFrameWindow *w = windowAt(win);
    if (w == NULL) return;
    w->active = active ? 1 : 0;
    w->visible = visible ? 1 : 0;
}

int ion_frame_wanted(void) {
    for (int i = 0; i < ION_MAX_WINDOWS; i++)
        if (s_windows[i].open && due(&s_windows[i])) return 1;
    return 0;
}

int ion_frame_emit(double timeMs) {
    int n = 0;
    for (int i = 0; i < ION_MAX_WINDOWS; i++) {
        IonFrameWindow *w = &s_windows[i];
        if (!w->open || !due(w)) continue;
        w->requested = 0;
        IonInputRecord r;
        memset(&r, 0, sizeof r);
        r.type = ION_INPUT_FRAME;
        r.window = i;
        r.x = timeMs;
        ion_input_push_record(&r);
        n++;
    }
    return n;
}

void ionWindowSetFramePolicy(IonWindowId id, int policy) {
    IonFrameWindow *w = windowAt(id);
    if (w == NULL) return;
    w->policy = policy == ION_FRAME_CONTINUOUS ? ION_FRAME_CONTINUOUS : ION_FRAME_ON_DEMAND;
}

void ionWindowSetFrameWhenInactive(IonWindowId id, int enabled) {
    IonFrameWindow *w = windowAt(id);
    if (w == NULL) return;
    w->whenInactive = enabled ? 1 : 0;
}

void ionWindowRequestFrame(IonWindowId id) {
    IonFrameWindow *w = windowAt(id);
    if (w == NULL) return;
    w->requested = 1;
}
