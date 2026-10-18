#ifndef ION_EXAMPLE_CHROME_MACOS_H
#define ION_EXAMPLE_CHROME_MACOS_H

// 1 when a status bar button titled `title` sits in a visible window at the top of a screen.
int chromeTrayVisible(const char *title);
// Clicks the status bar button titled `title`; 0 when there is none.
int chromeTrayClick(const char *title);
int chromeAppActive(void);
void chromeHideApp(void);
int chromeWindowIsKey(void *root);
int chromeWindowNumber(void *root);
// NSWindow.sharingType of the window of root.
int chromeSharingType(void *root);
// Refreshes the notification settings and delivered ids, read back with the two calls below.
void chromeNotifyQuery(void);
// UNAuthorizationStatus from the last query, -1 while it is pending.
int chromeNotifyAuth(void);
// 1 when `id` was in Notification Center at the last query, -1 while it is pending.
int chromeNotifyDelivered(const char *id);
// After `ms`, cancels the app's modal window and remembers whether it was an NSOpenPanel.
void chromeCancelModalAfter(int ms);
int chromeCancelledOpenPanel(void);

#endif
