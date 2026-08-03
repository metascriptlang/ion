// Pointer input event queue — small ring buffer, single-threaded FIFO.
//
// Producer: the render-surface host view's Cocoa event handlers (when the
// surface sits on top in INPUT_FULL it is the hit-test target, so it reliably
// receives mouse down/up/drag/move/scroll — SDL's content view, being below
// the webview, does not). Consumer: ionPollEvent → returns 4 → MS reads
// ionInput* and forwards into the native renderer.
//
// Coordinates are a FRACTION (0..1) of the surface, top-left origin — the same
// values the IonInputSink fast path delivers (single dispatch source in
// renderSurface.m), so the polled and sink paths agree.
// type: 1=button, 2=motion, 3=wheel; p1/p2 carry button/pressed, relX/relY,
// or wheel dx/dy per type (see bridge.h ionInput*).

#ifndef ION_INPUT_EVENTS_H
#define ION_INPUT_EVENTS_H

#ifdef __cplusplus
extern "C" {
#endif

int ion_input_push(int type, double x, double y, double p1, double p2);
int ion_input_pop(int *type, double *x, double *y, double *p1, double *p2);

#ifdef __cplusplus
}
#endif

#endif
