// IPC message queue — single-threaded, FIFO. Producer side is platform code
// (WKScriptMessageHandler, URL handler, tray click, hotkey, etc.). Consumer
// side is the event loop's poll function.
//
// Each message carries the id of the webview that sent it, or -1 for
// app-global producers (tray, hotkey, notification, deep link).
//
// push returns 0 on success, -1 on allocation failure (message dropped + a
// warning logged to stderr — non-fatal for IPC).
// pop returns 1 if a message was popped (last_* accessors now reflect it),
// 0 if queue empty. Strings returned by last_name/payload are valid until
// the next pop or push, then freed.

#ifndef ION_QUEUE_H
#define ION_QUEUE_H


#ifdef __cplusplus
extern "C" {
#endif

// Push a message from webview `webview` (-1 for app-global producers).
int         ion_queue_push_w(int webview, const char *name, const char *payload);

// App-global push, equivalent to ion_queue_push_w(-1, ...).
int         ion_queue_push(const char *name, const char *payload);

int         ion_queue_pop(void);
const char *ion_queue_last_name(void);
const char *ion_queue_last_payload(void);

// Source webview of the last-popped message, or -1 for an app-global one.
int         ion_queue_last_webview(void);

#ifdef __cplusplus
}
#endif

#endif
