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

static GPtrArray *s_messageButtons = NULL;

void ionMessageBoxAddButton(const char *label) {
    if (s_messageButtons == NULL) s_messageButtons = g_ptr_array_new_with_free_func(g_free);
    g_ptr_array_add(s_messageButtons, g_strdup(label));
}

typedef struct {
    int done;
    int index;
} ChooseResult;

static void onChosen(GObject *source, GAsyncResult *res, gpointer data) {
    ChooseResult *r = (ChooseResult *)data;
    GError *err = NULL;
    r->index = gtk_alert_dialog_choose_finish(GTK_ALERT_DIALOG(source), res, &err);
    if (err != NULL) {
        r->index = ION_MESSAGE_BOX_DISMISSED;
        g_error_free(err);
    }
    r->done = 1;
}

int ionMessageBoxRun(const char *title, const char *message, int style) {
    (void)style;
    GPtrArray *labels = s_messageButtons != NULL ? s_messageButtons : g_ptr_array_new_with_free_func(g_free);
    s_messageButtons = NULL;
    g_ptr_array_add(labels, NULL);

    GtkAlertDialog *dialog = gtk_alert_dialog_new("%s", title);
    gtk_alert_dialog_set_detail(dialog, message);
    gtk_alert_dialog_set_buttons(dialog, (const char *const *)labels->pdata);
    gtk_alert_dialog_set_modal(dialog, TRUE);

    ChooseResult r = {0, ION_MESSAGE_BOX_DISMISSED};
    GtkWindow *parent = s_mainWindow != NULL ? GTK_WINDOW(s_mainWindow) : NULL;
    gtk_alert_dialog_choose(dialog, parent, NULL, onChosen, &r);
    ionLinuxPumpUntil(&r.done, -1);
    g_object_unref(dialog);
    g_ptr_array_free(labels, TRUE);
    return r.index;
}
