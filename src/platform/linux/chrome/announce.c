// Ion Linux — screen reader announcement through GTK's AT-SPI bridge on the active window.

#include "../../bridge.h"

#include <gtk/gtk.h>

int ionAnnounce(const char *text) {
    GListModel *toplevels = gtk_window_get_toplevels();
    GtkWindow *active = NULL;
    for (guint i = 0; active == NULL && i < g_list_model_get_n_items(toplevels); i++) {
        GtkWindow *w = GTK_WINDOW(g_list_model_get_item(toplevels, i));
        if (gtk_window_is_active(w)) active = w;
        g_object_unref(w);
    }
    if (active == NULL) return ION_SERVICE_NO_WINDOW;
    gtk_accessible_announce(GTK_ACCESSIBLE(active), text, GTK_ACCESSIBLE_ANNOUNCEMENT_PRIORITY_MEDIUM);
    return ION_SERVICE_DONE;
}
