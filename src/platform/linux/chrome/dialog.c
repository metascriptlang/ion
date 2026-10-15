#include "../state.h"
#include "../../bridge.h"
#include "../internal.h"

#include <gtk/gtk.h>
#include <stdio.h>

typedef struct {
    int   done;
    char *path;
} OpenResult;

static void onOpened(GObject *source, GAsyncResult *res, gpointer data) {
    OpenResult *r = (OpenResult *)data;
    GError *err = NULL;
    GFile *file = gtk_file_dialog_open_finish(GTK_FILE_DIALOG(source), res, &err);
    if (file != NULL) {
        r->path = g_file_get_path(file);
        g_object_unref(file);
    } else if (!g_error_matches(err, GTK_DIALOG_ERROR, GTK_DIALOG_ERROR_DISMISSED)
            && !g_error_matches(err, GTK_DIALOG_ERROR, GTK_DIALOG_ERROR_CANCELLED)) {
        fprintf(stderr, "[ion] file dialog failed: %s\n", err->message);
    }
    if (err != NULL) g_error_free(err);
    r->done = 1;
}

msString ionFileOpen(void) {
    GtkWindow *parent = s_mainWindow != NULL ? GTK_WINDOW(s_mainWindow) : NULL;
    GtkFileDialog *dialog = gtk_file_dialog_new();
    gtk_file_dialog_set_title(dialog, "Open File");

    OpenResult r = {0, NULL};
    gtk_file_dialog_open(dialog, parent, NULL, onOpened, &r);
    ionLinuxPumpUntil(&r.done, -1);
    g_object_unref(dialog);

    msString out = cStringToMs(r.path);
    g_free(r.path);
    return out;
}
