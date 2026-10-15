#include <gtk/gtk.h>
#include "multiWindowLinux.h"

void probeUserClose(void *root) {
    GtkRoot *top = gtk_widget_get_root(GTK_WIDGET(root));
    if (top != NULL) gtk_window_close(GTK_WINDOW(top));
}
