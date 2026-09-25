#include "inputEvents.h"
#include "strconv.h"

#include <stdlib.h>
#include <string.h>

#define ION_INPUT_CAP 256

static IonInputRecord s_ring[ION_INPUT_CAP];
static int s_head = 0, s_tail = 0, s_count = 0;
static IonInputRecord s_current;

static char *dupText(const char *s) {
    if (s == NULL || s[0] == '\0') return NULL;
    size_t n = strlen(s) + 1;
    char *d = (char *)malloc(n);
    if (d) memcpy(d, s, n);
    return d;
}

int ion_input_push_record(const IonInputRecord *r) {
    if (s_count >= ION_INPUT_CAP) {
        // Drop oldest to keep the latest interaction responsive.
        free((void *)s_ring[s_head].text);
        s_head = (s_head + 1) % ION_INPUT_CAP;
        s_count--;
    }
    s_ring[s_tail] = *r;
    s_ring[s_tail].text = dupText(r->text);
    s_tail = (s_tail + 1) % ION_INPUT_CAP;
    s_count++;
    return 0;
}

int ion_input_push(int type, double x, double y, double p1, double p2) {
    IonInputRecord r;
    memset(&r, 0, sizeof r);
    r.type = type;
    r.surface = -1;
    r.x = x;
    r.y = y;
    r.p1 = p1;
    r.p2 = p2;
    return ion_input_push_record(&r);
}

int ion_input_next(void) {
    if (s_count == 0) return 0;
    free((void *)s_current.text);
    s_current = s_ring[s_head];
    s_head = (s_head + 1) % ION_INPUT_CAP;
    s_count--;
    return 1;
}

int      ionInputType(void)         { return s_current.type; }
int      ionInputSurface(void)      { return s_current.surface; }
double   ionInputX(void)            { return s_current.x; }
double   ionInputY(void)            { return s_current.y; }
double   ionInputP1(void)           { return s_current.p1; }
double   ionInputP2(void)           { return s_current.p2; }
int      ionInputKey(void)          { return s_current.key; }
int      ionInputScancode(void)     { return s_current.scancode; }
int      ionInputMods(void)         { return s_current.mods; }
int      ionInputConsumedMods(void) { return s_current.consumedMods; }
int      ionInputUnshifted(void)    { return (int)s_current.unshifted; }
msString ionInputText(void)         { return cStringToMs(s_current.text); }
