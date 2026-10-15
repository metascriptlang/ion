#include <gtk/gtk.h>
#include <gio/gio.h>
#include <stdio.h>
#include "chromeLinux.h"

static gboolean cancelNow(gpointer data) {
    g_cancellable_cancel(G_CANCELLABLE(data));
    return G_SOURCE_REMOVE;
}

static void onOpened(GObject *source, GAsyncResult *res, gpointer data) {
    GError *err = NULL;
    GFile *file = gtk_file_dialog_open_finish(GTK_FILE_DIALOG(source), res, &err);
    if (file != NULL) g_object_unref(file);
    fprintf(stderr, "chrome: dialog returned file=%d error=%s\n", file != NULL, err ? err->message : "none");
    if (err != NULL) g_error_free(err);
    *(int *)data = 1;
}

void chromeOpenAndCancel(void *root) {
    GtkWindow *main = GTK_WINDOW(gtk_widget_get_root(GTK_WIDGET(root)));
    GtkFileDialog *dialog = gtk_file_dialog_new();
    GCancellable *cancel = g_cancellable_new();
    int done = 0;
    gtk_file_dialog_open(dialog, main, cancel, onOpened, &done);
    g_timeout_add(1000, cancelNow, cancel);
    gint64 deadline = g_get_monotonic_time() + 5000000;
    while (!done && g_get_monotonic_time() < deadline) g_main_context_iteration(NULL, TRUE);
    fprintf(stderr, "chrome: cancellable open %s\n", done ? "completed" : "still pending after 5 s");
    g_object_unref(cancel);
    g_object_unref(dialog);
}

static GtkWindow *s_main;

static gboolean logToplevels(gpointer data) {
    (void)data;
    GListModel *tops = gtk_window_get_toplevels();
    int others = 0;
    for (guint i = 0; i < g_list_model_get_n_items(tops); i++) {
        GtkWindow *w = GTK_WINDOW(g_list_model_get_item(tops, i));
        if (w != s_main) others++;
        g_object_unref(w);
    }
    fprintf(stderr, "chrome: toplevels besides the main window while the dialog is open: %d\n", others);
    return G_SOURCE_REMOVE;
}

void chromeLogDialogToplevels(void *root) {
    s_main = GTK_WINDOW(gtk_widget_get_root(GTK_WIDGET(root)));
    g_timeout_add(1000, logToplevels, NULL);
}

int chromeBusHasOwner(const char *name) {
    GDBusConnection *c = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, NULL);
    if (c == NULL) return 0;
    GVariant *r = g_dbus_connection_call_sync(c, "org.freedesktop.DBus", "/org/freedesktop/DBus",
        "org.freedesktop.DBus", "NameHasOwner", g_variant_new("(s)", name),
        G_VARIANT_TYPE("(b)"), G_DBUS_CALL_FLAGS_NONE, 2000, NULL, NULL);
    if (r == NULL) return 0;
    gboolean has;
    g_variant_get(r, "(b)", &has);
    g_variant_unref(r);
    return has;
}
