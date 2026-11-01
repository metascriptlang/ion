// Ion Windows — a font file becomes a family GDI and DirectWrite name for this process only (FR_PRIVATE).

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdlib.h>

#include "../utf8.h"
#include "../../bridge.h"

int ionRegisterFont(const char *path) {
    wchar_t *wide = ionUtf8ToWide(path);
    if (wide == NULL) return 0;
    int added = AddFontResourceExW(wide, FR_PRIVATE, NULL);
    free(wide);
    return added > 0 ? 1 : 0;
}
