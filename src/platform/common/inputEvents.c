#include "inputEvents.h"

#define ION_INPUT_CAP 256

typedef struct {
    int    type;
    double x, y, p1, p2;
} ion_input_entry_t;

static ion_input_entry_t s_ring[ION_INPUT_CAP];
static int s_head = 0, s_tail = 0, s_count = 0;

int ion_input_push(int type, double x, double y, double p1, double p2) {
    if (s_count >= ION_INPUT_CAP) {
        // Drop oldest to keep the latest interaction responsive.
        s_head = (s_head + 1) % ION_INPUT_CAP;
        s_count--;
    }
    s_ring[s_tail].type = type;
    s_ring[s_tail].x = x;
    s_ring[s_tail].y = y;
    s_ring[s_tail].p1 = p1;
    s_ring[s_tail].p2 = p2;
    s_tail = (s_tail + 1) % ION_INPUT_CAP;
    s_count++;
    return 0;
}

int ion_input_pop(int *type, double *x, double *y, double *p1, double *p2) {
    if (s_count == 0) return 0;
    ion_input_entry_t *e = &s_ring[s_head];
    if (type) *type = e->type;
    if (x) *x = e->x;
    if (y) *y = e->y;
    if (p1) *p1 = e->p1;
    if (p2) *p2 = e->p2;
    s_head = (s_head + 1) % ION_INPUT_CAP;
    s_count--;
    return 1;
}
