// Wire protocol constants. Mirrors web/src/protocol.ts on the JS side.
// Both files MUST stay in sync — change one, change the other.

#ifndef ION_PROTOCOL_H
#define ION_PROTOCOL_H

// Internal channel name for Tauri-style request/response calls.
#define ION_CHANNEL_CALL      "__call"

// Internal channel name MS-side uses to deliver call() responses.
#define ION_CHANNEL_RESPONSE  "__response"

// Internal channel for window→window / broadcast events.
// JS posts envelope `{target, event, payload}` (target = label or "" for
// broadcast); MS-side runLoop intercepts and routes via ionEvalJSWindow.
#define ION_CHANNEL_EMIT      "__emit"

// Envelope field names used inside the __emit payload.
#define ION_FIELD_TARGET      "target"
#define ION_FIELD_EVENT       "event"
#define ION_FIELD_PAYLOAD     "payload"

// Envelope field name carrying the per-launch invoke_key.
#define ION_FIELD_KEY    "__key"

// Envelope field name carrying the source window's label (multi-window).
#define ION_FIELD_LABEL  "__label"

// Envelope field name for the response correlation id.
#define ION_FIELD_ID     "id"

// Envelope field name for the response value (success).
#define ION_FIELD_VALUE  "value"

// Envelope field name for the response error message (failure).
#define ION_FIELD_ERROR  "error"

#endif
