// Ion Linux — decide-policy signal handler.
//
// Mirrors macOS WKNavigationDelegate + Windows NavigationStarting. WebKit
// fires decide-policy for every navigation: initial load, link click, JS
// navigate, redirect. We consult common/navpolicy.c to decide:
//   - ALLOW    → let WebKit navigate in-page
//   - EXTERNAL → cancel + gtk_show_uri to open in default browser
//   - BLOCK    → cancel + log warn (file:// — opaque-origin trap)

#include "../state.h"
#include "../internal.h"
#include "../../common/navpolicy.h"

#include <webkit2/webkit2.h>
#include <ctype.h>
#include <stdio.h>
#include <string.h>

// Parse "scheme://host/..." into separate lowercase strings.
// Returns 1 on success, 0 if URL doesn't have a scheme. Empty host is fine.
static int parseSchemeHost(const char *url, char *schemeOut, int schemeCap,
                                              char *hostOut, int hostCap) {
    if (url == NULL) return 0;
    const char *colon = strchr(url, ':');
    if (colon == NULL) return 0;
    int schemeLen = (int)(colon - url);
    if (schemeLen <= 0 || schemeLen >= schemeCap) return 0;
    for (int i = 0; i < schemeLen; i++) {
        char c = url[i];
        if (c >= 'A' && c <= 'Z') c = (char)(c + ('a' - 'A'));
        schemeOut[i] = c;
    }
    schemeOut[schemeLen] = 0;

    hostOut[0] = 0;
    if (colon[1] == '/' && colon[2] == '/') {
        const char *hostStart = colon + 3;
        const char *hostEnd = hostStart;
        while (*hostEnd && *hostEnd != '/' && *hostEnd != '?' && *hostEnd != '#') hostEnd++;
        int hostLen = (int)(hostEnd - hostStart);
        if (hostLen >= hostCap) hostLen = hostCap - 1;
        for (int i = 0; i < hostLen; i++) {
            char c = hostStart[i];
            if (c >= 'A' && c <= 'Z') c = (char)(c + ('a' - 'A'));
            hostOut[i] = c;
        }
        hostOut[hostLen] = 0;
    }
    return 1;
}

static gboolean onDecidePolicy(WebKitWebView *view,
                               WebKitPolicyDecision *decision,
                               WebKitPolicyDecisionType type,
                               gpointer user_data) {
    (void)view; (void)user_data;

    // Only NavigationAction is interesting for our routing — let response
    // and new-window decisions flow through their defaults.
    if (type != WEBKIT_POLICY_DECISION_TYPE_NAVIGATION_ACTION
     && type != WEBKIT_POLICY_DECISION_TYPE_NEW_WINDOW_ACTION) {
        return FALSE;
    }

    WebKitNavigationPolicyDecision *navDecision =
        WEBKIT_NAVIGATION_POLICY_DECISION(decision);
    WebKitNavigationAction *action =
        webkit_navigation_policy_decision_get_navigation_action(navDecision);
    if (action == NULL) return FALSE;

    WebKitURIRequest *req = webkit_navigation_action_get_request(action);
    if (req == NULL) return FALSE;
    const char *uri = webkit_uri_request_get_uri(req);
    if (uri == NULL) return FALSE;

    char scheme[32] = {0};
    char host[256]  = {0};
    if (!parseSchemeHost(uri, scheme, (int)sizeof(scheme), host, (int)sizeof(host))) {
        return FALSE;
    }

    // WebKit's navigation type distinguishes user-clicked links from other
    // (JS navigate, redirect, initial load, etc.). Match mac's
    // WKNavigationTypeLinkActivated detection.
    WebKitNavigationType navType =
        webkit_navigation_action_get_navigation_type(action);
    int isUserClick = (navType == WEBKIT_NAVIGATION_TYPE_LINK_CLICKED) ? 1 : 0;

    ion_nav_decision_t outcome = ion_nav_decide(scheme, host, isUserClick);
    if (outcome == ION_NAV_EXTERNAL) {
        // Punt to default browser. gtk_show_uri_on_window is the modern API
        // (3.22+); older platforms can use gtk_show_uri but we target 3.22+.
        gtk_show_uri_on_window(GTK_WINDOW(s_mainWindow), uri, GDK_CURRENT_TIME, NULL);
        webkit_policy_decision_ignore(decision);
        return TRUE;
    }
    if (outcome == ION_NAV_BLOCK) {
        // file:// only — opaque-origin trap. Mirrors macOS message.
        fprintf(stderr,
            "[ion] navigation blocked: %s — file:// has opaque origin which "
            "breaks pushState/localStorage/SW. Use ion:// (bundled) or "
            "asset:// (scoped) instead. See vendor/ion/CUSTOM-PROTOCOL.md\n",
            uri);
        webkit_policy_decision_ignore(decision);
        return TRUE;
    }

    // ALLOW — let WebKit's default policy handle it.
    return FALSE;
}

void ionAttachNavHandler(WebKitWebView *view) {
    if (view == NULL) return;
    g_signal_connect(view, "decide-policy",
                     G_CALLBACK(onDecidePolicy), NULL);
}
