// Ion Linux - system font lookup and registration through fontconfig.

#include "../../bridge.h"
#include "../../common/strconv.h"

#include <fontconfig/fontconfig.h>
#include <stdlib.h>
#include <string.h>

#define ION_MAX_SYSTEM_FONTS 16

static char *s_paths[ION_MAX_SYSTEM_FONTS];
static int s_indices[ION_MAX_SYSTEM_FONTS];
static int s_count;

static void clear(void) {
    for (int i = 0; i < s_count; i++) free(s_paths[i]);
    s_count = 0;
}

static void add(const char *path, int index) {
    if (s_count == ION_MAX_SYSTEM_FONTS) return;
    for (int i = 0; i < s_count; i++) {
        if (s_indices[i] == index && strcmp(s_paths[i], path) == 0) return;
    }
    s_paths[s_count] = strdup(path);
    s_indices[s_count++] = index;
}

// Adds the sorted faces that draw the codepoint, colour faces only (color = 1) or the others
// (color = 0), keeping fontconfig's order: family, weight and slant closeness to the request.
static void addCovering(FcFontSet *set, FcChar32 codepoint, int color) {
    for (int i = 0; i < set->nfont; i++) {
        FcPattern *font = set->fonts[i];
        FcCharSet *charset = NULL;
        FcChar8 *file = NULL;
        int index = 0;
        FcBool isColor = FcFalse;
        if (FcPatternGetCharSet(font, FC_CHARSET, 0, &charset) != FcResultMatch || !FcCharSetHasChar(charset, codepoint)) continue;
        if (FcPatternGetString(font, FC_FILE, 0, &file) != FcResultMatch) continue;
        FcPatternGetInteger(font, FC_INDEX, 0, &index);
        FcPatternGetBool(font, FC_COLOR, 0, &isColor);
        if ((isColor != FcFalse) != (color != 0)) continue;
        // The high 16 bits name a variable font's named instance; the face is the low 16.
        add((const char *)file, index & 0xFFFF);
    }
}

int ionFindSystemFonts(int codepoint, int emoji, int weight, int italic, const char *family) {
    clear();
    if (codepoint < 0 || codepoint > 0x10FFFF || (codepoint >= 0xD800 && codepoint <= 0xDFFF)) return 0;
    if (!FcInit()) return 0;
    FcPattern *pattern = FcPatternCreate();
    if (family && *family) FcPatternAddString(pattern, FC_FAMILY, (const FcChar8 *)family);
    FcPatternAddInteger(pattern, FC_WEIGHT, FcWeightFromOpenType(weight > 0 ? weight : 400));
    FcPatternAddInteger(pattern, FC_SLANT, italic ? FC_SLANT_ITALIC : FC_SLANT_ROMAN);
    if (emoji) FcPatternAddBool(pattern, FC_COLOR, FcTrue);
    FcCharSet *wanted = FcCharSetCreate();
    FcCharSetAddChar(wanted, (FcChar32)codepoint);
    FcPatternAddCharSet(pattern, FC_CHARSET, wanted);
    FcConfigSubstitute(NULL, pattern, FcMatchPattern);
    FcDefaultSubstitute(pattern);
    FcResult result;
    FcFontSet *set = FcFontSort(NULL, pattern, FcFalse, NULL, &result);
    if (set) {
        // Colour faces first for emoji presentation and last for text, as Ghostty's discovery
        // scores a face's colour against the presentation (src/font/discovery.zig Score).
        addCovering(set, (FcChar32)codepoint, emoji ? 1 : 0);
        addCovering(set, (FcChar32)codepoint, emoji ? 0 : 1);
        FcFontSetDestroy(set);
    }
    FcCharSetDestroy(wanted);
    FcPatternDestroy(pattern);
    return s_count;
}

msString ionSystemFontPath(int i) { return (i >= 0 && i < s_count) ? cStringToMs(s_paths[i]) : MS_EMPTY_STRING; }

int ionSystemFontIndex(int i) { return (i >= 0 && i < s_count) ? s_indices[i] : 0; }

int ionRegisterFont(const char *path) {
    return FcInit() && FcConfigAppFontAddFile(NULL, (const FcChar8 *)path) ? 1 : 0;
}
