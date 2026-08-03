#include "navpolicy.h"
#include <string.h>
#include <ctype.h>

static int eq_lower(const char *a, const char *b) {
    if (a == NULL || b == NULL) return 0;
    while (*a && *b) {
        if (tolower((unsigned char)*a) != tolower((unsigned char)*b)) return 0;
        a++; b++;
    }
    return *a == 0 && *b == 0;
}

static int is_localhost(const char *host) {
    if (host == NULL) return 0;
    return eq_lower(host, "localhost")
        || strcmp(host, "127.0.0.1") == 0
        || strcmp(host, "0.0.0.0") == 0
        || strcmp(host, "::1") == 0;
}

ion_nav_decision_t ion_nav_decide(const char *scheme, const char *host, int is_user_click) {
    if (scheme == NULL) return ION_NAV_ALLOW;

    // file:// is a footgun on every modern webview: opaque origin breaks
    // pushState, localStorage scoping, SW registration, COOP/COEP/SAB.
    // Apps must use ion:// (bundled SPA) or asset:// (scoped disk file).
    if (eq_lower(scheme, "file")) {
        return ION_NAV_BLOCK;
    }

    if (eq_lower(scheme, "about")
     || eq_lower(scheme, "data")
     || is_localhost(host)) {
        return ION_NAV_ALLOW;
    }

    if (is_user_click && (eq_lower(scheme, "http")
                       || eq_lower(scheme, "https")
                       || eq_lower(scheme, "mailto"))) {
        return ION_NAV_EXTERNAL;
    }

    return ION_NAV_ALLOW;
}
