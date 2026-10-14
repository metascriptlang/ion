#ifndef ION_UTF16_H
#define ION_UTF16_H

#ifdef __cplusplus
extern "C" {
#endif

// UTF-16 code units taken by the first `chars` code points of a UTF-8 string
// (a code point above U+FFFF is two units). Stops at the end of the string.
int ion_utf16_units(const char *utf8, int chars);

#ifdef __cplusplus
}
#endif

#endif
