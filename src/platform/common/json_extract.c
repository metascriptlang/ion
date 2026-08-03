// See json_extract.h. Pure C — no platform headers.

#include "json_extract.h"

#include <stdlib.h>
#include <string.h>

char *ion_json_extract_string(const char *json, const char *key) {
    if (json == NULL || key == NULL) return NULL;
    int keyLen = (int)strlen(key);

    // Walk forward, finding each `"<X>"` and checking if X matches `key`.
    // The first matching key whose value parses as a string wins.
    const char *p = json;
    while (*p) {
        const char *q = strstr(p, "\"");
        if (q == NULL) return NULL;
        if (strncmp(q + 1, key, (size_t)keyLen) == 0 && q[1 + keyLen] == '"') {
            const char *r = q + 2 + keyLen;
            while (*r == ' ' || *r == '\t') r++;
            if (*r != ':') { p = q + 1; continue; }
            r++;
            while (*r == ' ' || *r == '\t') r++;
            if (*r != '"') return NULL;  // value is not a string — bail
            r++;  // now at first char of value

            // Decode into a growing malloc'd buffer.
            int cap = 64, len = 0;
            char *out = (char *)malloc((size_t)cap);
            if (out == NULL) return NULL;
            while (*r && *r != '"') {
                char c;
                if (*r == '\\' && r[1] != '\0') {
                    switch (r[1]) {
                        case '"':  c = '"';  break;
                        case '\\': c = '\\'; break;
                        case '/':  c = '/';  break;
                        case 'n':  c = '\n'; break;
                        case 't':  c = '\t'; break;
                        case 'r':  c = '\r'; break;
                        default:   c = r[1]; break;  // pass through
                    }
                    r += 2;
                } else {
                    c = *r;
                    r++;
                }
                if (len + 1 >= cap) {
                    cap *= 2;
                    char *grown = (char *)realloc(out, (size_t)cap);
                    if (grown == NULL) { free(out); return NULL; }
                    out = grown;
                }
                out[len++] = c;
            }
            out[len] = '\0';
            return out;
        }
        p = q + 1;
    }
    return NULL;
}
