// Ion Linux — OS notifications via libnotify.
//
// libnotify wraps the freedesktop.org `org.freedesktop.Notifications` DBus
// service — same channel used by GNOME Shell, KDE Plasma, Mako (sway),
// dunst, etc. notify_init lazy-singleton's the app name; subsequent calls
// reuse the existing session.
//
// Click-routing: libnotify's "closed" signal fires on dismissal regardless
// of reason (timeout, click, user dismissed); to distinguish a *click*, we
// register a "default" action — when the user clicks the notification body
// (or its primary button), the action callback fires with the id we passed
// in as user_data, and we route that to the `notification.click` IPC. The
// `closed` callback then cleans up. Some daemons (Mako) don't surface
// default-action clicks — they'll only fire `closed`; that matches mac's
// behavior when the user dismisses without clicking (no IPC).

#include "../state.h"
#include "../../bridge.h"

#include <libnotify/notify.h>
#include <gtk/gtk.h>
#include <stdlib.h>
#include <string.h>

static int s_notifyInited = 0;

static void onDefaultAction(NotifyNotification *n, char *action, gpointer user_data) {
    (void)n; (void)action;
    const char *id = (const char *)user_data;
    ionEnqueueMessage("notification.click", id != NULL ? id : "");
    if (s_mainWindow != NULL) {
        gtk_window_present(GTK_WINDOW(s_mainWindow));
    }
}

// Closed signal fires once per notification — frees the id strdup we attached
// as user_data + drops the notification object reference.
static void onNotifyClosed(NotifyNotification *n, gpointer user_data) {
    g_free(user_data);
    g_object_unref(n);
}

void ionNotify(const char *title, const char *body, const char *id) {
    if (title == NULL) title = "";
    if (body  == NULL) body  = "";
    if (id    == NULL || id[0] == '\0') id = "ion-notif";

    if (!s_notifyInited) {
        // App name shows up in the notification daemon's UI grouping.
        notify_init("Ion");
        s_notifyInited = 1;
    }

    NotifyNotification *n = notify_notification_new(title, body, NULL);
    if (n == NULL) return;
    notify_notification_set_urgency(n, NOTIFY_URGENCY_NORMAL);

    // Heap-copy id so its lifetime spans the async daemon round-trip; freed
    // in onNotifyClosed (always fires) regardless of which path (action or
    // timeout) the notification took.
    char *idCopy = g_strdup(id);
    notify_notification_add_action(n,
        "default", "Open",
        NOTIFY_ACTION_CALLBACK(onDefaultAction),
        idCopy, NULL);
    g_signal_connect(n, "closed", G_CALLBACK(onNotifyClosed), idCopy);

    GError *err = NULL;
    if (!notify_notification_show(n, &err)) {
        if (err != NULL) g_error_free(err);
        // Failed to show — free our copy + drop the object. closed signal
        // never fires on a failed show.
        g_free(idCopy);
        g_object_unref(n);
    }
    // Ownership of `n` (and idCopy) now lives with the libnotify async
    // delivery + the closed signal handler.
}
