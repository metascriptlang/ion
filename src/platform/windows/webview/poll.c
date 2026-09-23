// Ion Windows — event pump + IPC message accessor.
//
// The blocking event loop pumps Win32 messages while idle. Each tick:
//   1. drain one queued IPC msg → return 2
//   2. pump all available Win32 messages (PeekMessage) — non-blocking
//   3. if quit posted → return 1
//   4. drain again → return 2
//   5. else sleep 16ms (60Hz) → return 0
//
// WebView2 async callbacks (env created, controller created, web message
// received, navigation starting) are delivered through the Win32 message
// pump — DispatchMessageW below drives them.
//
// `ionEvalJS` is owned by webview/eval.cpp (C++ side touches the COM
// objects). This file only handles Win32 plumbing + queue drain.

#include "../state.h"
#include "../internal.h"
#include "../../bridge.h"
#include "../../common/queue.h"
#include "../../common/inputEvents.h"

int ionPollEvent(void) {
    if (ion_queue_pop()) return 2;
    if (ion_input_next()) return 4;

    MSG msg;
    while (PeekMessageW(&msg, NULL, 0, 0, PM_REMOVE)) {
        if (msg.message == WM_QUIT) return 1;
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }
    ionWinKeyFlush();

    if (ion_queue_pop()) return 2;
    if (ion_input_next()) return 4;

    // Window closed (s_mainHwnd cleared by WM_DESTROY) but no WM_QUIT yet
    // somehow — treat as quit so runLoop can exit cleanly.
    if (s_mainHwnd == NULL) return 1;

    Sleep(16);  // ~60Hz idle pace, matches macOS SDL_WaitEventTimeout(16)
    return 0;
}

msString ionMessageName(void)    { return cStringToMs(ion_queue_last_name()); }
msString ionMessagePayload(void) { return cStringToMs(ion_queue_last_payload()); }
