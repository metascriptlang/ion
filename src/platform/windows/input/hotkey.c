// Ion Windows — global hotkey via Win32 RegisterHotKey.
//
// Phase 1 stub. Phase 4 will:
//   1. Maintain a fixed slot table (16 hotkeys, mirrors mac).
//   2. Register via RegisterHotKey(hwnd, id, modifiers, vk_code).
//   3. Listen for WM_HOTKEY in the window proc, translate id → IPC msg
//      "hotkey" with payload = id (string).
//
// macOS modifier bitmask (1=cmd, 2=shift, 4=alt, 8=ctrl) maps to Win32 MOD_*:
//   cmd → MOD_WIN, shift → MOD_SHIFT, alt → MOD_ALT, ctrl → MOD_CONTROL.
// keyCode passed in is the macOS Carbon virtual key — we'll need a
// translation table mac-vk → win-vk in Phase 4 (or accept Win VK directly
// when host is windows; TBD).

#include "../state.h"
#include "../../bridge.h"

int ionRegisterHotkey(int modifiers, int keyCode, int id) {
    (void)modifiers; (void)keyCode; (void)id;
    return -1;  // not yet implemented — match mac's "Carbon refused" sentinel
}

void ionUnregisterHotkey(int id) {
    (void)id;
}
