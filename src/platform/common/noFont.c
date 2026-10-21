// Ion Windows and Linux - no system font lookup yet (TODO.md): every codepoint finds none.

#include "../bridge.h"

msString ionFindSystemFont(int codepoint, int emoji, int weight, int italic, const char *family) {
	(void)codepoint; (void)emoji; (void)weight; (void)italic; (void)family;
	return MS_EMPTY_STRING;
}

int ionSystemFontIndex(void) { return 0; }
