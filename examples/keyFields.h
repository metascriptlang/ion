#ifndef ION_EXAMPLE_KEY_FIELDS_H
#define ION_EXAMPLE_KEY_FIELDS_H

#ifdef __cplusplus
extern "C" {
#endif

// For examples/keyFields.ms: activates a keyboard layout ("00000409", "00000407") for this
// thread; returns 0 when Windows cannot load it.
int kfLayout(const char *klid);
// Unloads the layouts kfLayout loaded that were not installed before.
void kfUnloadLayouts(void);
// Presses and releases one key on ion's main window procedure with the modifiers held in the
// thread keyboard state; TranslateMessage makes the WM_CHAR or WM_SYSCHAR from that state and the
// layout. altGr holds Ctrl and right Alt. Returns how many character messages it dispatched.
int kfKey(int vk, int ctrl, int shift, int alt, int altGr);
void kfClose(void);

#ifdef __cplusplus
}
#endif

#endif
