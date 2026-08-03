// Ion Linux — WebKitGTK custom URI scheme handler.
//
// Phase 4.5 Linux side. Mirrors mac WKURLSchemeHandler + Win
// WebResourceRequested. webkit_web_context_register_uri_scheme installs
// a per-scheme callback on the shared WebContext; the callback reads the
// requested URI, dispatches through the cross-platform protoReg lookup,
// and replies via webkit_uri_scheme_request_finish_with_response.
//
// Constraint (verified against tauri-runtime-wry/src/lib.rs:5121-5136 + wry
// src/webkitgtk/web_context.rs): scheme can only register once per
// WebContext lifetime. We call this from ionSetupWebview BEFORE the view is
// created — registration latches into the context permanently.

#include "../state.h"
#include "../internal.h"
#include "../../common/protoReg.h"

#include <webkit2/webkit2.h>
#include <gio/gio.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Strip "scheme://host" prefix from URI, leaving "/path?q#f" suffix.
// Returns pointer into the input (or "/" if no path part).
static const char *stripSchemeHost(const char *url) {
    if (url == NULL) return "/";
    const char *colon = strstr(url, "://");
    if (colon == NULL) return "/";
    const char *after = colon + 3;
    while (*after && *after != '/' && *after != '?' && *after != '#') after++;
    if (*after == 0) return "/";
    return after;
}

// Per-request callback. WebKit hands us a WebKitURISchemeRequest; we route
// through ionProtoLookup and finish with a GInputStream-backed response.
static void onSchemeRequest(WebKitURISchemeRequest *request, gpointer user_data) {
    (void)user_data;

    const char *uri = webkit_uri_scheme_request_get_uri(request);
    if (uri == NULL) {
        webkit_uri_scheme_request_finish_error(
            request,
            g_error_new_literal(g_quark_from_static_string("ion"), 400, "no uri"));
        return;
    }

    // Parse scheme from URI prefix. ion:// → "ion".
    char scheme[32] = {0};
    const char *colon = strchr(uri, ':');
    if (colon != NULL) {
        int len = (int)(colon - uri);
        if (len > 0 && len < (int)sizeof(scheme)) {
            for (int i = 0; i < len; i++) {
                char c = uri[i];
                if (c >= 'A' && c <= 'Z') c = (char)(c + ('a' - 'A'));
                scheme[i] = c;
            }
        }
    }

    const char *rawPath = stripSchemeHost(uri);
    unsigned char *body = NULL;
    size_t bodyLen = 0;
    const char *mime = NULL;
    int status = 200;
    IonProtoStatus lr = ionProtoLookup(scheme, rawPath, &body, &bodyLen, &mime, &status);

    if (lr == IonProtoNoScheme || mime == NULL) {
        webkit_uri_scheme_request_finish_error(
            request,
            g_error_new_literal(g_quark_from_static_string("ion"), 404, "no scheme handler"));
        if (body) free(body);
        return;
    }

    // GMemoryInputStream takes ownership of the buffer (with g_free as destroy
    // notify). Our body was malloc'd in protoReg — wrap it as a GBytes copy
    // instead of transferring ownership, simpler than mixing allocators.
    GBytes *bytes = g_bytes_new(body, bodyLen);
    if (body) free(body);

    GInputStream *stream = g_memory_input_stream_new_from_bytes(bytes);
    g_bytes_unref(bytes);

    // Use the response variant so we can set the HTTP status code. Plain
    // webkit_uri_scheme_request_finish() doesn't carry status.
    WebKitURISchemeResponse *response =
        webkit_uri_scheme_response_new(stream, (gint64)bodyLen);
    webkit_uri_scheme_response_set_status(response, (guint)status, NULL);
    webkit_uri_scheme_response_set_content_type(response, mime);

    // Permissive CORS for own-scheme — matches mac/win handlers. Lets
    // fetch() inside the page hit the same origin without surprise.
    SoupMessageHeaders *headers =
        soup_message_headers_new(SOUP_MESSAGE_HEADERS_RESPONSE);
    soup_message_headers_append(headers, "Access-Control-Allow-Origin", "*");
    webkit_uri_scheme_response_set_http_headers(response, headers);
    // headers ownership transfers to response — do NOT unref.

    webkit_uri_scheme_request_finish_with_response(request, response);

    g_object_unref(response);
    g_object_unref(stream);
}

void ionInstallSchemeHandlers(WebKitWebContext *ctx) {
    if (ctx == NULL) return;
    int n = ionProtoSchemeCount();
    if (n <= 0) return;

    for (int i = 0; i < n; i++) {
        const char *scheme = ionProtoSchemeAt(i);
        if (scheme == NULL || scheme[0] == 0) continue;
        // GLib already deduplicates re-registration by emitting a warning;
        // proto registry is frozen-by-now so we won't double-register the
        // same scheme within one process. WebKit's per-context lifetime
        // constraint still holds — context is process-wide, single-use.
        webkit_web_context_register_uri_scheme(ctx, scheme,
            onSchemeRequest, NULL, NULL);
        // Mark our scheme as a secure context so SW + COOP/COEP etc. work.
        WebKitSecurityManager *sec = webkit_web_context_get_security_manager(ctx);
        webkit_security_manager_register_uri_scheme_as_secure(sec, scheme);
    }
}
