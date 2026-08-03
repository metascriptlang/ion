#include "mime.h"
#include <string.h>
#include <ctype.h>

static int extEq(const char *a, const char *b) {
    while (*a && *b) {
        if (tolower((unsigned char)*a) != tolower((unsigned char)*b)) return 0;
        a++; b++;
    }
    return *a == 0 && *b == 0;
}

const char *ionMimeForPath(const char *path) {
    static const char DEFAULT[] = "application/octet-stream";
    if (path == NULL) return DEFAULT;

    const char *dot = strrchr(path, '.');
    if (dot == NULL || dot[1] == 0) return DEFAULT;
    const char *ext = dot + 1;

    // Strip query/fragment if any leaked through (defense-in-depth — caller
    // should strip first, but cheap to handle here too).
    size_t len = 0;
    while (ext[len] && ext[len] != '?' && ext[len] != '#') len++;

    char buf[16];
    if (len >= sizeof(buf)) return DEFAULT;
    for (size_t i = 0; i < len; i++) buf[i] = (char)tolower((unsigned char)ext[i]);
    buf[len] = 0;

    if (extEq(buf, "html") || extEq(buf, "htm"))  return "text/html; charset=utf-8";
    if (extEq(buf, "js")   || extEq(buf, "mjs"))  return "application/javascript; charset=utf-8";
    if (extEq(buf, "css"))                          return "text/css; charset=utf-8";
    if (extEq(buf, "json"))                         return "application/json; charset=utf-8";
    if (extEq(buf, "svg"))                          return "image/svg+xml";
    if (extEq(buf, "png"))                          return "image/png";
    if (extEq(buf, "jpg")  || extEq(buf, "jpeg")) return "image/jpeg";
    if (extEq(buf, "gif"))                          return "image/gif";
    if (extEq(buf, "webp"))                         return "image/webp";
    if (extEq(buf, "ico"))                          return "image/x-icon";
    if (extEq(buf, "woff2"))                        return "font/woff2";
    if (extEq(buf, "woff"))                         return "font/woff";
    if (extEq(buf, "ttf"))                          return "font/ttf";
    if (extEq(buf, "otf"))                          return "font/otf";
    if (extEq(buf, "wasm"))                         return "application/wasm";
    if (extEq(buf, "map"))                          return "application/json";
    if (extEq(buf, "txt"))                          return "text/plain; charset=utf-8";

    return DEFAULT;
}
