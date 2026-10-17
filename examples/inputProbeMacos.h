#ifndef ION_EXAMPLE_INPUT_PROBE_MACOS_H
#define ION_EXAMPLE_INPUT_PROBE_MACOS_H

// Synthetic AppKit input for examples/contentInputMacos.ms: each call posts NSEvents to the
// app's own queue, so they take the path a physical device's events take (SDL pumps them,
// [NSApp sendEvent:] runs the local monitors, the window hit-tests). Points are device pixels
// of the client area, top-left origin, as in Ion's records. `root` is windowRoot.
// Not covered: the wheel (an NSEvent made from a CGEvent scroll carries no window, and
// CGEventPostToPid needs Accessibility) and a right button (a synthetic NSEvent reports
// buttonNumber 0, which AppKit and SDL read as left).
void ipActivate(void *root);
void ipClick(void *root, int x, int y, int button, int mods);
// One key press and release. `chars` is what the layout produced (UTF-8), `bare` the same key
// without modifiers; mods are ION_MOD_* bits.
void ipKey(void *root, int keyCode, const char *chars, const char *bare, int mods);
// What an input method sends: marked text with the caret at `caretUtf16`, then a commit.
void ipMarked(void *root, const char *utf8, int caretUtf16);
void ipCommit(void *root, const char *utf8);
// 1 when the first responder is the WKWebView (or inside it).
int ipWebviewIsFirstResponder(void *root);

#endif
