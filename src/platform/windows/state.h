// Ion Windows — shared state + helper declarations.
//
// All static globals live in state.c. Other implementation files reference
// them via these extern declarations. Same pattern as macos/state.h —
// keeping state in one place makes lifecycle reasoning straightforward.

#ifndef ION_WINDOWS_STATE_H
#define ION_WINDOWS_STATE_H

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#ifdef __cplusplus
extern "C" {
#endif

// ---- Windows-only globals --------------------------------------------------
//
// IPC queue + invoke_key live in src/platform/common/ as plain C — every
// platform reuses them. Only types/handles that are intrinsically Win32 stay here.

extern HWND      s_mainHwnd;
extern HINSTANCE s_hInstance;

// Opaque pointer to webview/internal.hpp `WebView2State` (C++ struct holding
// ComPtr<ICoreWebView2Controller> + ComPtr<ICoreWebView2> + event tokens).
// C code only sees it as `void *` — only the .cpp files under webview/
// dereference it. NULL when WebView2 isn't initialized yet.
extern void     *s_webview2State;

// Cold-start deep link URL captured at ionInit time (argv[1] matching the
// `<scheme>://...` pattern registered by the installer). Empty when no URL
// was passed. Replayed as a "deeplink" IPC after the window is created.
extern char      s_coldStartUrl[2048];

// ---- Convenience wrapper around the common queue --------------------------

// Thin shim: Win32 narrow string → const char * → ion_queue_push.
// Lets Windows callers avoid manual conversion at every call site.
void ionEnqueueMessage(const char *name, const char *payload);

#ifdef __cplusplus
}
#endif

#endif
