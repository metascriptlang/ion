#include <gtk/gtk.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "windowControlsLinux.h"

static GtkWidget *s_root;
static int s_savedErr = -1;
static char s_errPath[] = "/tmp/ionWcErrXXXXXX";

void wcBind(void *root) { s_root = GTK_WIDGET(root); }

static GtkWindow *win(void) { return GTK_WINDOW(gtk_widget_get_root(s_root)); }

static GdkToplevelState toplevelState(void) {
    GdkSurface *s = gtk_native_get_surface(GTK_NATIVE(win()));
    return s ? gdk_toplevel_get_state(GDK_TOPLEVEL(s)) : 0;
}

int wcRootW(void) { return gtk_widget_get_width(s_root); }
int wcRootH(void) { return gtk_widget_get_height(s_root); }
int wcTitleIs(const char *utf8) {
    const char *t = gtk_window_get_title(win());
    return t != NULL && strcmp(t, utf8) == 0;
}
int wcVisible(void) { return gtk_widget_get_visible(GTK_WIDGET(win())); }
int wcMapped(void) { return gtk_widget_get_mapped(GTK_WIDGET(win())); }
int wcMinimized(void) { return (toplevelState() & GDK_TOPLEVEL_STATE_MINIMIZED) != 0; }
int wcMaximized(void) { return gtk_window_is_maximized(win()) && (toplevelState() & GDK_TOPLEVEL_STATE_MAXIMIZED) != 0; }
int wcDecorated(void) { return gtk_window_get_decorated(win()); }
int wcActive(void) { return gtk_window_is_active(win()); }
int wcIsWayland(void) {
    const char *name = G_OBJECT_TYPE_NAME(gdk_display_get_default());
    return strstr(name, "Wayland") != NULL;
}
void wcUserClose(void) { gtk_window_close(win()); }

void wcStderrBegin(void) {
    strcpy(s_errPath, "/tmp/ionWcErrXXXXXX");
    int fd = mkstemp(s_errPath);
    if (fd < 0) return;
    fflush(stderr);
    s_savedErr = dup(2);
    dup2(fd, 2);
    close(fd);
}

int wcStderrContains(const char *needle) {
    if (s_savedErr < 0) return 0;
    fflush(stderr);
    dup2(s_savedErr, 2);
    close(s_savedErr);
    s_savedErr = -1;
    int found = 0;
    FILE *f = fopen(s_errPath, "r");
    if (f != NULL) {
        char line[1024];
        while (fgets(line, sizeof line, f) != NULL) {
            fputs(line, stderr);
            if (strstr(line, needle) != NULL) found = 1;
        }
        fclose(f);
    }
    unlink(s_errPath);
    return found;
}
