// Ion Linux — native file dialog via GtkFileChooserDialog.
//
// v0: single-file selection, any type. Modal — blocks until dismissed.
// Returns the selected path or MS_EMPTY_STRING on cancel (matches mac
// NSOpenPanel + Windows IFileOpenDialog contracts).
//
// Parent: gtk_file_chooser_dialog_new takes a GtkWindow parent so the dialog
// renders centered + treated as modal-to-app. We pass the main window when
// it exists; otherwise NULL (renders as a top-level — also valid).

#include "../state.h"
#include "../../bridge.h"
#include "../internal.h"

#include <gtk/gtk.h>
#include <stdlib.h>
#include <string.h>

msString ionFileOpen(void) {
    GtkWindow *parent = s_mainWindow != NULL ? GTK_WINDOW(s_mainWindow) : NULL;

    GtkWidget *dialog = gtk_file_chooser_dialog_new(
        "Open File",
        parent,
        GTK_FILE_CHOOSER_ACTION_OPEN,
        "_Cancel", GTK_RESPONSE_CANCEL,
        "_Open",   GTK_RESPONSE_ACCEPT,
        NULL);
    if (dialog == NULL) return MS_EMPTY_STRING;

    gint res = gtk_dialog_run(GTK_DIALOG(dialog));
    msString out = MS_EMPTY_STRING;
    if (res == GTK_RESPONSE_ACCEPT) {
        char *filename = gtk_file_chooser_get_filename(GTK_FILE_CHOOSER(dialog));
        if (filename != NULL) {
            out = cStringToMs(filename);
            g_free(filename);
        }
    }
    gtk_widget_destroy(dialog);
    return out;
}
