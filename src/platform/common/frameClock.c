#include "frameClock.h"
#include "inputEvents.h"
#include "../bridge.h"

#include <string.h>

#define ION_FRAME_SURFACES 64
#define ION_FRAME_WINDOWS  64

typedef struct {
    int open;
    int win;
    int policy;
    int whenInactive;
    int requested;
} IonFrameSurface;

typedef struct {
    int known;
    int active;
    int visible;
} IonFrameWindow;

static IonFrameSurface s_surfaces[ION_FRAME_SURFACES];
static IonFrameWindow  s_windows[ION_FRAME_WINDOWS];

static IonFrameSurface *surfaceAt(int surf) {
    if (surf < 0 || surf >= ION_FRAME_SURFACES || !s_surfaces[surf].open) return NULL;
    return &s_surfaces[surf];
}

static const IonFrameWindow *windowAt(int win) {
    static const IonFrameWindow shown = { 1, 1, 1 };
    if (win < 0 || win >= ION_FRAME_WINDOWS || !s_windows[win].known) return &shown;
    return &s_windows[win];
}

static int due(const IonFrameSurface *s) {
    const IonFrameWindow *w = windowAt(s->win);
    if (!w->visible) return 0;
    if (s->requested) return 1;
    return s->policy == ION_FRAME_CONTINUOUS && (w->active || s->whenInactive);
}

void ion_frame_surface_open(int surf, int win) {
    if (surf < 0 || surf >= ION_FRAME_SURFACES) return;
    memset(&s_surfaces[surf], 0, sizeof s_surfaces[surf]);
    s_surfaces[surf].open = 1;
    s_surfaces[surf].win = win;
    s_surfaces[surf].policy = ION_FRAME_ON_DEMAND;
}

void ion_frame_surface_close(int surf) {
    if (surf < 0 || surf >= ION_FRAME_SURFACES) return;
    memset(&s_surfaces[surf], 0, sizeof s_surfaces[surf]);
}

void ion_frame_window_state(int win, int active, int visible) {
    if (win < 0 || win >= ION_FRAME_WINDOWS) return;
    s_windows[win].known = 1;
    s_windows[win].active = active ? 1 : 0;
    s_windows[win].visible = visible ? 1 : 0;
}

int ion_frame_wanted(void) {
    for (int i = 0; i < ION_FRAME_SURFACES; i++)
        if (s_surfaces[i].open && due(&s_surfaces[i])) return 1;
    return 0;
}

int ion_frame_emit(double timeMs) {
    int n = 0;
    for (int i = 0; i < ION_FRAME_SURFACES; i++) {
        IonFrameSurface *s = &s_surfaces[i];
        if (!s->open || !due(s)) continue;
        s->requested = 0;
        IonInputRecord r;
        memset(&r, 0, sizeof r);
        r.type = ION_INPUT_FRAME;
        r.surface = i;
        r.x = timeMs;
        ion_input_push_record(&r);
        n++;
    }
    return n;
}

void ionRenderSurfaceSetFramePolicy(IonRenderSurfaceId surf, int policy) {
    IonFrameSurface *s = surfaceAt(surf);
    if (s == NULL) return;
    s->policy = policy == ION_FRAME_CONTINUOUS ? ION_FRAME_CONTINUOUS : ION_FRAME_ON_DEMAND;
}

void ionRenderSurfaceSetFrameWhenInactive(IonRenderSurfaceId surf, int enabled) {
    IonFrameSurface *s = surfaceAt(surf);
    if (s == NULL) return;
    s->whenInactive = enabled ? 1 : 0;
}

void ionRenderSurfaceRequestFrame(IonRenderSurfaceId surf) {
    IonFrameSurface *s = surfaceAt(surf);
    if (s == NULL) return;
    s->requested = 1;
}
