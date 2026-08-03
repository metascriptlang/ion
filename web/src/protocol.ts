// Wire protocol constants. Mirrors src/platform/common/protocol.h on the
// native side. Both files MUST stay in sync — change one, change the other.

/** Internal channel name for Tauri-style request/response calls. */
export const CHANNEL_CALL = "__call";

/** Internal channel name MS-side uses to deliver call() responses. */
export const CHANNEL_RESPONSE = "__response";

/** Internal channel for window→window / broadcast events. */
export const CHANNEL_EMIT = "__emit";

/** Envelope field name carrying the per-launch invoke_key. */
export const FIELD_KEY = "__key";

/** Envelope field name carrying the source window's label. */
export const FIELD_LABEL = "__label";

/** Envelope field name for the response correlation id. */
export const FIELD_ID = "id";

/** Envelope field name for the response value (success). */
export const FIELD_VALUE = "value";

/** Envelope field name for the response error message (failure). */
export const FIELD_ERROR = "error";

/** __emit envelope: target window label ("" for broadcast). */
export const FIELD_TARGET = "target";

/** __emit envelope: event name being routed. */
export const FIELD_EVENT = "event";

/** __emit envelope: the event payload. */
export const FIELD_PAYLOAD = "payload";
