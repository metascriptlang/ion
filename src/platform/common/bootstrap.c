// See bootstrap.h. Pure C, no platform headers — the produced JS is
// platform-agnostic except for the one-line transport body the caller passes.

#include "bootstrap.h"

#include <stdio.h>
#include <stdlib.h>

// The literal `__key` and `__label` field names below MUST match
// ION_FIELD_KEY / ION_FIELD_LABEL in protocol.h. Keep them in sync manually
// — the JS string literal cannot use the C macro directly. The
// web/src/protocol.ts file mirrors the same constants on the JS side.
// Main-frame guard at top of the IIFE: bail immediately if running inside
// an iframe. macOS WKWebView already restricts our injection to the main
// frame via `forMainFrameOnly:YES`, but WebView2's
// AddScriptToExecuteOnDocumentCreated has no per-frame flag — the same
// script is injected into every frame. This check makes `window.__ion__`
// undefined in iframes regardless of platform, so embedded cross-origin
// frames can't reach the IPC API.
static const char kJsTemplate[] =
    "(function(){"
    "  if (window.self !== window.top) return;"
    "  var __ionKey = '%s';"
    "  var __ionLabel = '%s';"
    "  var __recv = null;"
    "  var nativePost = function(envelope) { %s };"
    "  Object.defineProperty(window, '__ion__', {"
    "    value: Object.freeze({"
    "      label: __ionLabel,"
    "      post: function(name, payload) {"
    "        nativePost({"
    "          __key: __ionKey,"
    "          __label: __ionLabel,"
    "          name: String(name),"
    "          payload: payload === undefined || payload === null ? '' : String(payload)"
    "        });"
    "      },"
    "      setReceiver: function(fn) { __recv = fn; },"
    "      _dispatch: function(name, payload) { if (__recv) __recv(name, payload); }"
    "    }),"
    "    writable: false, configurable: false"
    "  });"
    "  ['log','warn','error','info'].forEach(function(level){"
    "    var orig = console[level];"
    "    console[level] = function(){"
    "      try { window.__ion__.post('console.'+level, Array.from(arguments).map(String).join(' ')); } catch(e) {}"
    "      orig && orig.apply(console, arguments);"
    "    };"
    "  });"
    "  window.addEventListener('error', function(e){"
    "    window.__ion__.post('console.error','window.onerror: '+(e.message||e)+' @ '+(e.filename||'?')+':'+(e.lineno||'?'));"
    "  });"
    "  window.addEventListener('unhandledrejection', function(e){"
    "    window.__ion__.post('console.error','unhandledrejection: '+(e.reason && e.reason.stack || e.reason || e));"
    "  });"
    "})();";

char *ion_build_bootstrap_js_w(const char *invokeKey, const char *windowLabel,
                               const char *nativePostBody) {
    if (invokeKey == NULL)      invokeKey = "";
    if (windowLabel == NULL)    windowLabel = "";
    if (nativePostBody == NULL) nativePostBody = "";

    int needed = snprintf(NULL, 0, kJsTemplate, invokeKey, windowLabel, nativePostBody);
    if (needed < 0) return NULL;

    char *buf = (char *)malloc((size_t)needed + 1);
    if (buf == NULL) return NULL;

    snprintf(buf, (size_t)needed + 1, kJsTemplate, invokeKey, windowLabel, nativePostBody);
    return buf;
}

char *ion_build_bootstrap_js(const char *invokeKey, const char *nativePostBody) {
    return ion_build_bootstrap_js_w(invokeKey, "", nativePostBody);
}
