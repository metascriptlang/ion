// Input event queue — small ring buffer, single-threaded FIFO.
//
// Producers: the platform's render-surface host (pointer, key, text, IME
// preedit, focus, resize). Consumer: ionPollEvent → ion_input_next → returns 4
// → MS reads the current record through the ionInput* accessors, defined once
// in inputEvents.c for every platform.
//
// Pointer coordinates are a FRACTION (0..1) of the surface, top-left origin —
// the same values the IonInputSink fast path delivers. Field meaning per type
// is documented beside the accessors in bridge.h.

#ifndef ION_INPUT_EVENTS_H
#define ION_INPUT_EVENTS_H

#ifdef __cplusplus
extern "C" {
#endif

#define ION_INPUT_BUTTON  1
#define ION_INPUT_MOTION  2
#define ION_INPUT_WHEEL   3
#define ION_INPUT_KEY     4
#define ION_INPUT_TEXT    5
#define ION_INPUT_PREEDIT 6
#define ION_INPUT_FOCUS   7
#define ION_INPUT_RESIZE  8

typedef struct {
    int         type;
    int         surface;
    double      x, y, p1, p2;
    int         key;
    int         scancode;
    int         mods;
    int         consumedMods;
    unsigned    unshifted;
    const char *text;
} IonInputRecord;

int ion_input_push(int type, double x, double y, double p1, double p2);
// Copies r->text; the caller keeps ownership of its buffer.
int ion_input_push_record(const IonInputRecord *r);

// Moves the oldest record into the slot the ionInput* accessors read.
// Returns 1 when a record was popped, 0 when the queue is empty.
int ion_input_next(void);

#ifdef __cplusplus
}
#endif

#endif
