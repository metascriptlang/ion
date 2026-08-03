// Ion Linux — JS→MS IPC via WebKitGTK script-message-received.
//
// Mirrors macOS WKScriptMessageHandler + Windows WebMessageReceived.
// JS calls `window.webkit.messageHandlers.ion.postMessage({__key, name, payload})`
// from the bootstrap (see common/bootstrap.c). We:
//   1. Pull the JS value as JSON, parse it
//   2. Validate the invoke_key (closure-scoped token, see common/protocol.h)
//   3. Enqueue (name, payload) onto the IPC queue for MS-side `listen()` to drain

#include "../state.h"
#include "../internal.h"
#include "../../common/invokekey.h"
#include "../../common/protocol.h"
#include "../../common/json_extract.h"

#include <webkit2/webkit2.h>
#include <jsc/jsc.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// "script-message-received::ion" — fired when JS calls
// window.webkit.messageHandlers.ion.postMessage(...).
static void onScriptMessage(WebKitUserContentManager *ucm,
                            WebKitJavascriptResult *result,
                            gpointer user_data) {
    (void)ucm; (void)user_data;

    JSCValue *jsValue = webkit_javascript_result_get_js_value(result);
    if (jsValue == NULL) return;

    // Serialize the JS object to JSON. We use the same JSON-string-shape
    // contract as mac (NSDictionary → keys "__key", "name", "payload") and
    // Windows (WebMessageAsJson → identical shape).
    gchar *json = jsc_value_to_json(jsValue, 0);
    if (json == NULL) return;

    // Extract fields. invoke_key gate first — anything missing or wrong
    // gets dropped silently.
    char *key = ion_json_extract_string(json, ION_FIELD_KEY);
    if (key == NULL || !ion_invoke_key_verify(key)) {
        fprintf(stderr, "[ion] IPC rejected: invalid invoke_key\n");
        free(key);
        g_free(json);
        return;
    }
    free(key);

    char *name = ion_json_extract_string(json, "name");
    if (name == NULL) { g_free(json); return; }
    char *payload = ion_json_extract_string(json, "payload");

    ionEnqueueMessage(name, payload ? payload : "");

    free(name);
    free(payload);
    g_free(json);
}

void ionAttachMessageHandler(WebKitUserContentManager *ucm) {
    if (ucm == NULL) return;
    // Register the "ion" message channel — bootstrap script posts to it.
    webkit_user_content_manager_register_script_message_handler(ucm, "ion");
    g_signal_connect(ucm, "script-message-received::ion",
                     G_CALLBACK(onScriptMessage), NULL);
}
