// Minimal JSON string-field extractor — pure C, no dependencies.
//
// Used by platform code that receives webview→native IPC envelopes serialized
// as JSON and needs to validate `__key` + read `name` + `payload` fields
// before enqueueing to the IPC queue. The envelope shape is fixed (see
// common/bootstrap.c JS template + common/protocol.h field names), so we
// don't need a full parser — just "find `"<key>":` and read the string value".
//
// Platform usage:
//   - Windows: WebView2 `get_WebMessageAsJson` returns a JSON string;
//     messaging.cpp uses this to extract fields. Mac WKWebView auto-converts
//     to NSDictionary, no parser needed there.
//   - Future Linux (WebKitGTK): webkit_web_view_run_javascript_finish returns
//     JSON for postMessage payloads — will reuse this.

#ifndef ION_JSON_EXTRACT_H
#define ION_JSON_EXTRACT_H

#ifdef __cplusplus
extern "C" {
#endif

// Find a `"<key>":"<value>"` field anywhere in `json`. Returns a malloc'd
// UTF-8 string holding `<value>` (caller frees) or NULL if the key is
// missing or the value isn't a quoted string.
//
// Decodes the basic JSON string escapes: \" \\ \/ \n \t \r. Does NOT handle
// `\uXXXX` (the JS bootstrap produces ASCII keys + app-level values; if you
// pass non-ASCII, you'll get the escape byte verbatim — acceptable for our
// envelope but watch out if reused for arbitrary JSON).
char *ion_json_extract_string(const char *json, const char *key);

#ifdef __cplusplus
}
#endif

#endif
