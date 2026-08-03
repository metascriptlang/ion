// Webview navigation policy — pure decision function. Platform navigation
// delegate (WKNavigationDelegate, ICoreWebView2NavigationStartingEventHandler,
// WebKitGTK decide-policy signal) extracts URL parts + click-vs-programmatic
// flag, calls this, applies the decision via its own API.
//
// Decision rules:
//   1. file://                                     → BLOCK (Tauri-style strict;
//      opaque-origin trap, use ion:// or asset:// instead)
//   2. about: / data: / localhost host             → ALLOW (own loads, dev)
//   3. user-clicked http(s)/mailto                 → EXTERNAL (open in browser)
//   4. anything else                               → ALLOW (in-app SPA routing,
//      includes ion:// / asset:// / custom schemes)

#ifndef ION_NAVPOLICY_H
#define ION_NAVPOLICY_H

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    ION_NAV_ALLOW    = 0,
    ION_NAV_EXTERNAL = 1,  // open in default browser (cancel in-webview)
    ION_NAV_BLOCK    = 2,  // cancel + log warn (file:// trap)
} ion_nav_decision_t;

// `scheme` and `host` are extracted from the URL (lowercased or any case).
// `is_user_click` non-zero means "navigation initiated by user clicking a link"
// (vs programmatic / SPA routing / initial load).
ion_nav_decision_t ion_nav_decide(const char *scheme, const char *host, int is_user_click);

#ifdef __cplusplus
}
#endif

#endif
