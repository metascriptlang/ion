#ifndef ION_EXAMPLE_SERVICES_MACOS_H
#define ION_EXAMPLE_SERVICES_MACOS_H

void svActivate(void);
// 1 when the key window's first responder is a WKWebView or inside one.
int svWebviewHasFocus(void);
// The class of the key window's first responder.
const char *svFirstResponderClass(void);
// Within `ms`, in every run loop mode, notes the windows a share picker adds and dismisses them.
void svDismissShareWithin(int ms);
// Class names of the picker windows seen, "" when none appeared.
const char *svShareWindowsSeen(void);
// Visible windows other than the app's own key window and the picker's, read when called.
int svShareWindowsLeft(void);
// After `ms`, presses the modal alert's button titled `title`, or aborts the modal when "".
void svAnswerAlertAfter(int ms, const char *title);
// The modal alert's style and button titles as "style:a|b|c", read when it was answered.
const char *svAlertSeen(void);

#endif
