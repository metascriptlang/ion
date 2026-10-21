// Ion Windows and Linux - no system font lookup yet (TODO.md): every codepoint finds none.

#include "../bridge.h"

int ionFindSystemFonts(int codepoint, int emoji, int weight, int italic, const char *family) {
	(void)codepoint; (void)emoji; (void)weight; (void)italic; (void)family;
	return 0;
}

msString ionSystemFontPath(int i) { (void)i; return MS_EMPTY_STRING; }

int ionSystemFontIndex(int i) { (void)i; return 0; }
