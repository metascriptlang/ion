#ifndef ION_EXAMPLE_INPUT_PROBE_MACOS_H
#define ION_EXAMPLE_INPUT_PROBE_MACOS_H

// Synthetic AppKit input for examples/contentInputMacos.ms: each call posts NSEvents to the
// app's own queue, so they take the path a physical device's events take (SDL pumps them,
// [NSApp sendEvent:] runs the local monitors, the window hit-tests). Points are device pixels
// of the client area, top-left origin, as in Ion's records. `root` is windowRoot.
// Buttons, motion and the wheel are CGEvents turned into NSEvents, so the button number, the
// scroll phase and the precise-delta flag are the ones a device sets.
void ipActivate(void *root);
void ipClick(void *root, int x, int y, int button, int mods);
// One press and release of button 1 (left), 2 (right) or 3 (middle).
void ipButton(void *root, int x, int y, int button, int mods);
void ipMove(void *root, int x, int y, int mods);
// `down` lines (or pixels with unitPixels) toward the user, `right` to the right.
void ipScroll(void *root, int x, int y, int unitPixels, int down, int right, int mods);
// The pointer entering and leaving the content, routed through its tracking area (AppKit drops
// an exit for an area it never saw entered).
void ipLeave(void *root, int mods);
// Selects an installed input source by id, enabling it if needed; ipRestoreInputSource puts
// back the person's source and disables what this enabled. 0 when it is not installed.
int ipSelectInputSource(const char *sourceId);
void ipRestoreInputSource(void);
// 1 when the app is active and the window key: an input method serves only that app.
int ipAppActive(void *root);
// One press and release of a key as the keyboard sends it (a CGEvent), so Text Services and
// the selected input method see it; the characters come from the selected layout.
void ipDeviceKey(void *root, int keyCode);
// One key press and release. `chars` is what the layout produced (UTF-8), `bare` the same key
// without modifiers; mods are ION_MOD_* bits.
void ipKey(void *root, int keyCode, const char *chars, const char *bare, int mods);
// What an input method sends: marked text with the caret at `caretUtf16`, then a commit.
void ipMarked(void *root, const char *utf8, int caretUtf16);
void ipCommit(void *root, const char *utf8);
// 1 when the first responder is the WKWebView (or inside it).
int ipWebviewIsFirstResponder(void *root);

#endif
