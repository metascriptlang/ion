#include <gtk/gtk.h>
#include "content.h"
#include <stdio.h>

int contentAttach(void *parent, void *child, int above) {
    (void)above;
    if (parent == NULL || child == NULL) return 0;
    gtk_fixed_put(GTK_FIXED(parent), GTK_WIDGET(child), 0, 0);
    gtk_widget_set_visible(GTK_WIDGET(child), TRUE);
    return 1;
}

void contentDetach(void *parent, void *child) {
    if (parent != NULL && child != NULL) gtk_fixed_remove(GTK_FIXED(parent), GTK_WIDGET(child));
}

void contentMove(void *node, int x, int y, int w, int h) {
    if (node == NULL) return;
    GtkWidget *widget = GTK_WIDGET(node);
    GtkWidget *parent = gtk_widget_get_parent(widget);
    int scale = gtk_widget_get_scale_factor(widget);
    if (scale < 1) scale = 1;
    if (parent != NULL) gtk_fixed_move(GTK_FIXED(parent), widget, x / scale, y / scale);
    gtk_widget_set_size_request(widget, w / scale, h / scale);
}

void *contentPanel(void *device, int w, int h, const char *text, unsigned rgb) {
    (void)device; (void)w; (void)h; (void)rgb;
    fprintf(stderr, "[content] contentPanel('%s'): drawn panels are Windows-only in this example\n", text);
    return NULL;
}

void contentRelease(void *node) { (void)node; }
