#include "utf16.h"

int ion_utf16_units(const char *utf8, int chars) {
    int units = 0;
    for (const unsigned char *p = (const unsigned char *)utf8; chars > 0 && *p != '\0'; chars--) {
        // A lead byte of 0xF0 or more starts a four-byte sequence: a surrogate pair.
        units += *p >= 0xF0 ? 2 : 1;
        p++;
        while ((*p & 0xC0) == 0x80) p++;
    }
    return units;
}
