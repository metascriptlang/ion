// Minimal EventToken.h stub for MinGW / zig c++ targets.
//
// WebView2.h #includes <EventToken.h> from Windows Runtime headers (winrt/...).
// MinGW-w64 (which zig bundles) does not ship the WinRT header set, so we
// vendor just the one struct WebView2.h references.
//
// EventRegistrationToken is the registration handle returned by WebView2's
// `add_*` event-subscription methods and consumed by the matching `remove_*`.
// Its shape is stable across the WinRT public surface and matches Microsoft's
// official definition byte-for-byte (a single INT64 value).
//
// Reference: https://learn.microsoft.com/en-us/uwp/api/windows.foundation.eventregistrationtoken

#ifndef __EventToken_h__
#define __EventToken_h__

#ifdef __cplusplus
extern "C" {
#endif

typedef struct EventRegistrationToken {
    __int64 value;
} EventRegistrationToken;

#ifdef __cplusplus
}
#endif

#endif // __EventToken_h__
