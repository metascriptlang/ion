// Custom URI scheme registry implementation. See protoReg.h.
//
// Storage: static arrays. v0 caps schemes at 8 and asset roots at 16. Brief
// design has no consumer needing more; bump caps if a real case arises.

#include "protoReg.h"
#include "mime.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <sys/stat.h>

#define MAX_SCHEMES   8
#define MAX_SCHEME_LEN 32
#define MAX_PATH_LEN 1024
#define MAX_ASSET_ROOTS 16

typedef struct {
    char scheme[MAX_SCHEME_LEN];
    char baseDir[MAX_PATH_LEN];
} SchemeEntry;

static SchemeEntry sSchemes[MAX_SCHEMES];
static int sSchemeCount = 0;

static char sAssetRoots[MAX_ASSET_ROOTS][MAX_PATH_LEN];
static int sAssetRootCount = 0;
static int sAssetRegistered = 0;

static int sFrozen = 0;

// ---- helpers --------------------------------------------------------------

static int eqLower(const char *a, const char *b) {
    if (a == NULL || b == NULL) return 0;
    while (*a && *b) {
        if (tolower((unsigned char)*a) != tolower((unsigned char)*b)) return 0;
        a++; b++;
    }
    return *a == 0 && *b == 0;
}

static int pathReadableDir(const char *path) {
    struct stat st;
    if (stat(path, &st) != 0) return 0;
    return S_ISDIR(st.st_mode);
}

// Find next slash, treat both `/` and `\` (Windows).
static const char *nextSep(const char *p) {
    while (*p && *p != '/' && *p != '\\') p++;
    return p;
}

// Reject `..` segments. Returns 1 if path is safe, 0 if traversal attempted.
// Empty path / `.` segments are allowed.
static int pathIsSafe(const char *path) {
    if (path == NULL) return 1;
    const char *p = path;
    while (*p) {
        if (*p == '/') p++;
        const char *segEnd = nextSep(p);
        size_t segLen = (size_t)(segEnd - p);
        if (segLen == 2 && p[0] == '.' && p[1] == '.') return 0;
        p = segEnd;
        if (*p == '\\') p++;
    }
    return 1;
}

// Percent-decode in place — output never longer than input.
static void percentDecode(char *s) {
    char *r = s;
    char *w = s;
    while (*r) {
        if (*r == '%' && r[1] && r[2]) {
            char hi = (char)tolower((unsigned char)r[1]);
            char lo = (char)tolower((unsigned char)r[2]);
            int hv = (hi >= '0' && hi <= '9') ? (hi - '0')
                   : (hi >= 'a' && hi <= 'f') ? (10 + hi - 'a') : -1;
            int lv = (lo >= '0' && lo <= '9') ? (lo - '0')
                   : (lo >= 'a' && lo <= 'f') ? (10 + lo - 'a') : -1;
            if (hv >= 0 && lv >= 0) {
                *w++ = (char)((hv << 4) | lv);
                r += 3;
                continue;
            }
        }
        *w++ = *r++;
    }
    *w = 0;
}

// Strip query string + fragment.
static void cleanPath(char *path) {
    char *q = strchr(path, '?');
    if (q) *q = 0;
    char *h = strchr(path, '#');
    if (h) *h = 0;
}

// ---- registration ---------------------------------------------------------

IonProtoStatus ionProtoRegister(const char *scheme, const char *baseDir) {
    if (sFrozen) return IonProtoFrozen;
    if (scheme == NULL || scheme[0] == 0) return IonProtoInvalid;
    if (baseDir == NULL || baseDir[0] == 0) return IonProtoInvalid;
    if (strlen(scheme) >= MAX_SCHEME_LEN) return IonProtoInvalid;
    if (strlen(baseDir) >= MAX_PATH_LEN) return IonProtoInvalid;
    if (!pathReadableDir(baseDir)) return IonProtoInvalid;

    for (int i = 0; i < sSchemeCount; i++) {
        if (eqLower(sSchemes[i].scheme, scheme)) return IonProtoDuplicate;
    }
    if (sSchemeCount >= MAX_SCHEMES) return IonProtoInvalid;

    SchemeEntry *e = &sSchemes[sSchemeCount++];
    // Store lower-cased scheme (URLs schemes are case-insensitive per RFC 3986).
    size_t i = 0;
    for (; scheme[i] && i < MAX_SCHEME_LEN - 1; i++) {
        e->scheme[i] = (char)tolower((unsigned char)scheme[i]);
    }
    e->scheme[i] = 0;
    strncpy(e->baseDir, baseDir, MAX_PATH_LEN - 1);
    e->baseDir[MAX_PATH_LEN - 1] = 0;
    return IonProtoOk;
}

IonProtoStatus ionProtoRegisterAsset(const char *roots) {
    if (sFrozen) return IonProtoFrozen;
    if (sAssetRegistered) return IonProtoDuplicate;
    if (roots == NULL) return IonProtoInvalid;

    sAssetRootCount = 0;
    const char *p = roots;
    while (*p && sAssetRootCount < MAX_ASSET_ROOTS) {
        const char *end = p;
        while (*end && *end != '\n') end++;
        size_t len = (size_t)(end - p);
        if (len > 0 && len < MAX_PATH_LEN) {
            memcpy(sAssetRoots[sAssetRootCount], p, len);
            sAssetRoots[sAssetRootCount][len] = 0;
            sAssetRootCount++;
        }
        p = end;
        if (*p == '\n') p++;
    }
    sAssetRegistered = 1;
    return IonProtoOk;
}

void ionProtoFreeze(void) {
    sFrozen = 1;
}

int ionProtoIsFrozen(void) {
    return sFrozen;
}

int ionProtoSchemeCount(void) {
    return sSchemeCount;
}

const char *ionProtoSchemeAt(int i) {
    if (i < 0 || i >= sSchemeCount) return NULL;
    return sSchemes[i].scheme;
}

void ionProtoResetForTests(void) {
    sSchemeCount = 0;
    sAssetRootCount = 0;
    sAssetRegistered = 0;
    sFrozen = 0;
}

// ---- lookup helpers -------------------------------------------------------

static int pathUnderRoot(const char *path, const char *root) {
    size_t rl = strlen(root);
    if (strncmp(path, root, rl) != 0) return 0;
    // Either exact match or next char is a separator.
    if (path[rl] == 0 || path[rl] == '/' || path[rl] == '\\') return 1;
    return 0;
}

static unsigned char *readFileAll(const char *path, size_t *outLen) {
    FILE *fp = fopen(path, "rb");
    if (!fp) return NULL;
    if (fseek(fp, 0, SEEK_END) != 0) { fclose(fp); return NULL; }
    long sz = ftell(fp);
    if (sz < 0) { fclose(fp); return NULL; }
    if (fseek(fp, 0, SEEK_SET) != 0) { fclose(fp); return NULL; }
    unsigned char *buf = (unsigned char *)malloc((size_t)sz + 1);
    if (!buf) { fclose(fp); return NULL; }
    size_t got = fread(buf, 1, (size_t)sz, fp);
    fclose(fp);
    if (got != (size_t)sz) { free(buf); return NULL; }
    buf[sz] = 0;
    *outLen = (size_t)sz;
    return buf;
}

// ---- lookup ---------------------------------------------------------------

IonProtoStatus ionProtoLookup(
    const char *scheme,
    const char *rawPath,
    unsigned char **outBody,
    size_t *outLen,
    const char **outMime,
    int *outStatus
) {
    if (scheme == NULL) return IonProtoNoScheme;
    if (outBody) *outBody = NULL;
    if (outLen)  *outLen  = 0;

    // Asset scheme has dedicated logic.
    if (eqLower(scheme, "asset")) {
        if (!sAssetRegistered) return IonProtoNoScheme;

        char path[MAX_PATH_LEN];
        if (rawPath == NULL) rawPath = "/";
        strncpy(path, rawPath, MAX_PATH_LEN - 1);
        path[MAX_PATH_LEN - 1] = 0;
        cleanPath(path);
        percentDecode(path);
        if (!pathIsSafe(path)) {
            if (outMime) *outMime = "text/plain; charset=utf-8";
            if (outStatus) *outStatus = 403;
            return IonProtoForbidden;
        }

        // asset:// uses absolute path: /Users/.../photo.jpg
        const char *abs = path;
        int allowed = 0;
        for (int i = 0; i < sAssetRootCount; i++) {
            if (pathUnderRoot(abs, sAssetRoots[i])) { allowed = 1; break; }
        }
        if (!allowed) {
            if (outMime) *outMime = "text/plain; charset=utf-8";
            if (outStatus) *outStatus = 403;
            return IonProtoForbidden;
        }

        size_t len = 0;
        unsigned char *body = readFileAll(abs, &len);
        if (!body) {
            if (outMime) *outMime = "text/plain; charset=utf-8";
            if (outStatus) *outStatus = 404;
            return IonProtoNotFound;
        }
        if (outBody) *outBody = body; else free(body);
        if (outLen)  *outLen  = len;
        if (outMime) *outMime = ionMimeForPath(abs);
        if (outStatus) *outStatus = 200;
        return IonProtoOk;
    }

    // Static-protocol path: look up baseDir for scheme.
    const char *baseDir = NULL;
    for (int i = 0; i < sSchemeCount; i++) {
        if (eqLower(sSchemes[i].scheme, scheme)) {
            baseDir = sSchemes[i].baseDir;
            break;
        }
    }
    if (baseDir == NULL) return IonProtoNoScheme;

    char path[MAX_PATH_LEN];
    if (rawPath == NULL || rawPath[0] == 0) rawPath = "/index.html";
    strncpy(path, rawPath, MAX_PATH_LEN - 1);
    path[MAX_PATH_LEN - 1] = 0;
    cleanPath(path);
    percentDecode(path);
    if (!pathIsSafe(path)) {
        if (outMime) *outMime = "text/plain; charset=utf-8";
        if (outStatus) *outStatus = 403;
        return IonProtoForbidden;
    }

    // Empty path or just `/` → /index.html
    const char *suffix = path;
    if (suffix[0] == 0 || (suffix[0] == '/' && suffix[1] == 0)) suffix = "/index.html";

    char abs[MAX_PATH_LEN * 2 + 2];
    int n = snprintf(abs, sizeof(abs), "%s%s%s",
                     baseDir,
                     (suffix[0] == '/' ? "" : "/"),
                     suffix);
    if (n < 0 || (size_t)n >= sizeof(abs)) {
        if (outMime) *outMime = "text/plain; charset=utf-8";
        if (outStatus) *outStatus = 404;
        return IonProtoNotFound;
    }

    size_t len = 0;
    unsigned char *body = readFileAll(abs, &len);
    if (!body) {
        if (outMime) *outMime = "text/plain; charset=utf-8";
        if (outStatus) *outStatus = 404;
        return IonProtoNotFound;
    }
    if (outBody) *outBody = body; else free(body);
    if (outLen)  *outLen  = len;
    if (outMime) *outMime = ionMimeForPath(abs);
    if (outStatus) *outStatus = 200;
    return IonProtoOk;
}

// ---- public bridge fns (bridge.h) -----------------------------------------

int ionRegisterStaticProtocol(const char *scheme, const char *baseDir) {
    IonProtoStatus s = ionProtoRegister(scheme, baseDir);
    if (s == IonProtoOk) return 1;
    if (s == IonProtoFrozen) {
        fprintf(stderr,
            "[ion] ionRegisterStaticProtocol(\"%s\") called after ionOpen() — ignored\n",
            scheme ? scheme : "(null)");
    }
    return 0;
}

int ionRegisterAssetScope(const char *allowedRoots) {
    IonProtoStatus s = ionProtoRegisterAsset(allowedRoots);
    if (s == IonProtoOk) return 1;
    if (s == IonProtoFrozen) {
        fprintf(stderr, "[ion] ionRegisterAssetScope called after ionOpen() — ignored\n");
    }
    return 0;
}
