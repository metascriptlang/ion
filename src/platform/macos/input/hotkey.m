// Ion macOS — global (system-wide) hotkey via Carbon RegisterEventHotKey.
//
// Carbon hotkeys are exclusive: once registered, only this app receives the
// combo. Works even when the app is not focused. No Accessibility permission
// required (NSEvent monitor would need it; we don't use that).
//
// Hit → "hotkey" IPC message with payload = id (as decimal string).
//
// Slot table is fixed at 16. ionRegisterHotkey returns:
//    1 — success
//    0 — slot table full
//   -1 — Carbon refused (combo taken by OS or another app)

#import "../state.h"
#import "../../bridge.h"
#import <Carbon/Carbon.h>
#include "../../common/queue.h"
#include <stdio.h>

typedef struct {
    int             id;
    EventHotKeyRef  ref;
} IonHotkey;

static IonHotkey       s_hotkeys[16];
static int             s_hotkeyCount   = 0;
static EventHandlerRef s_hotkeyHandler = NULL;

static OSStatus hotkeyCallback(EventHandlerCallRef next, EventRef event, void *userData) {
    (void)next; (void)userData;
    EventHotKeyID hk;
    if (GetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID,
                          NULL, sizeof(hk), NULL, &hk) == noErr) {
        char buf[16];
        snprintf(buf, sizeof(buf), "%u", (unsigned)hk.id);
        ion_queue_push("hotkey", buf);
    }
    return noErr;
}

static void ensureHandler(void) {
    if (s_hotkeyHandler != NULL) return;
    EventTypeSpec spec = { kEventClassKeyboard, kEventHotKeyPressed };
    InstallApplicationEventHandler(&hotkeyCallback, 1, &spec, NULL, &s_hotkeyHandler);
}

int ionRegisterHotkey(int modifiers, int keyCode, int id) {
    if (s_hotkeyCount >= (int)(sizeof(s_hotkeys) / sizeof(s_hotkeys[0]))) return 0;
    ensureHandler();

    UInt32 carbonMods = 0;
    if (modifiers & 1) carbonMods |= cmdKey;
    if (modifiers & 2) carbonMods |= shiftKey;
    if (modifiers & 4) carbonMods |= optionKey;
    if (modifiers & 8) carbonMods |= controlKey;

    EventHotKeyID hk = { .signature = 'IONh', .id = (UInt32)id };
    EventHotKeyRef ref = NULL;
    OSStatus status = RegisterEventHotKey((UInt32)keyCode, carbonMods, hk,
                                           GetApplicationEventTarget(), 0, &ref);
    if (status != noErr || ref == NULL) return -1;

    s_hotkeys[s_hotkeyCount++] = (IonHotkey){ .id = id, .ref = ref };
    return 1;
}

void ionUnregisterHotkey(int id) {
    for (int i = 0; i < s_hotkeyCount; i++) {
        if (s_hotkeys[i].id == id) {
            UnregisterEventHotKey(s_hotkeys[i].ref);
            s_hotkeys[i] = s_hotkeys[--s_hotkeyCount];
            return;
        }
    }
}
