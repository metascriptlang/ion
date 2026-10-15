#ifndef ION_EXAMPLE_TEXT_FILTER_H
#define ION_EXAMPLE_TEXT_FILTER_H

#ifdef __cplusplus
extern "C" {
#endif

// Sends one character message straight to ion's main window procedure, for examples/textFilter.ms.
// sys: 1 sends WM_SYSCHAR, 0 sends WM_CHAR. vk: nonzero brackets the character with WM_KEYDOWN and
// WM_KEYUP of that virtual key. ctrl, alt: held through the thread keyboard state for the call.
void tfSend(int sys, int unit, int vk, int ctrl, int alt);
void tfClose(void);

#ifdef __cplusplus
}
#endif

#endif
