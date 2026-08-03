// IPC message queue — single-threaded, FIFO. Producer side is platform code
// (WKScriptMessageHandler, URL handler, tray click, hotkey, etc.). Consumer
// side is the event loop's poll function.
//
// Each message carries an optional windowId tag identifying which window
// originated it. JS messages from a webview are tagged with the slot id of
// that webview; app-global producers (tray, hotkey, notification) push with
// ION_WINDOW_INVALID and the consumer treats those as un-targeted.
//
// push returns 0 on success, -1 on allocation failure (message dropped + a
// warning logged to stderr — non-fatal for IPC).
// pop returns 1 if a message was popped (last_* accessors now reflect it),
// 0 if queue empty. Strings returned by last_name/payload are valid until
// the next pop or push, then freed.

#ifndef ION_QUEUE_H
#define ION_QUEUE_H

#include "windowRegistry.h"   // IonWindowId, ION_WINDOW_INVALID

#ifdef __cplusplus
extern "C" {
#endif

// Tagged push — the new path. windowId may be ION_WINDOW_INVALID for
// un-targeted (app-global) messages.
int         ion_queue_push_w(IonWindowId windowId, const char *name, const char *payload);

// Backward-compat wrapper — equivalent to ion_queue_push_w(ION_WINDOW_INVALID, ...).
// Callers being migrated to multi-window should switch to the tagged form.
int         ion_queue_push(const char *name, const char *payload);

int         ion_queue_pop(void);
const char *ion_queue_last_name(void);
const char *ion_queue_last_payload(void);

// Window id of the last-popped message, or ION_WINDOW_INVALID if the push
// was un-tagged. Valid until the next pop/push.
IonWindowId ion_queue_last_window_id(void);

#ifdef __cplusplus
}
#endif

#endif
