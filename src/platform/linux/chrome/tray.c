// StatusNotifierItem over D-Bus through ayatana-appindicator-glib: the GTK3 appindicator
// cannot load into a GTK4 process. The library has no primary-click signal, so a one-item
// menu "Open" fires tray.click, and the same action is the middle-click target.

#include "../state.h"
#include "../internal.h"
#include "../../bridge.h"

#include <ayatana-appindicator.h>
#include <gtk/gtk.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

static AppIndicator *s_indicator = NULL;

static void onOpenActivate(GSimpleAction *action, GVariant *param, gpointer data) {
    (void)action; (void)param; (void)data;
    ionEnqueueMessage("tray.click", "");
    ionLinuxPresentMain();
}

static int watcherHasOwner(void) {
    GDBusConnection *c = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, NULL);
    if (c == NULL) return 0;
    GVariant *r = g_dbus_connection_call_sync(c, "org.freedesktop.DBus", "/org/freedesktop/DBus",
        "org.freedesktop.DBus", "NameHasOwner", g_variant_new("(s)", "org.kde.StatusNotifierWatcher"),
        G_VARIANT_TYPE("(b)"), G_DBUS_CALL_FLAGS_NONE, 2000, NULL, NULL);
    if (r == NULL) return 0;
    gboolean has;
    g_variant_get(r, "(b)", &has);
    g_variant_unref(r);
    return has;
}

static void ensureIndicator(void) {
    if (s_indicator != NULL) return;

    if (!watcherHasOwner()) {
        fprintf(stderr, "[ion] installTray: no StatusNotifierWatcher on the session bus, "
                        "so no tray host shows the icon; it appears if a host starts later\n");
    }

    s_indicator = app_indicator_new(
        "ion-tray",
        "application-x-executable",
        APP_INDICATOR_CATEGORY_APPLICATION_STATUS);

    GMenu *menu = g_menu_new();
    g_menu_append(menu, "Open", "indicator.open");
    GSimpleActionGroup *actions = g_simple_action_group_new();
    GSimpleAction *open = g_simple_action_new("open", NULL);
    g_signal_connect(open, "activate", G_CALLBACK(onOpenActivate), NULL);
    g_action_map_add_action(G_ACTION_MAP(actions), G_ACTION(open));
    g_object_unref(open);

    app_indicator_set_menu(s_indicator, menu);
    app_indicator_set_actions(s_indicator, actions);
    app_indicator_set_secondary_activate_target(s_indicator, "open");
    g_object_unref(menu);
    g_object_unref(actions);
    app_indicator_set_status(s_indicator, APP_INDICATOR_STATUS_ACTIVE);
}

void ionInstallTray(const char *title) {
    ensureIndicator();
    app_indicator_set_label(s_indicator,
                            (title != NULL && title[0] != '\0') ? title : "ion",
                            "");
}

static char *resolveIconPath(const char *pngPath) {
    if (pngPath == NULL || pngPath[0] == '\0') return NULL;

    struct stat st;
    if (stat(pngPath, &st) == 0 && S_ISREG(st.st_mode)) {
        return g_strdup(pngPath);
    }

    const char *resDir = msStringToCString(ionResourcePath());
    if (resDir != NULL && resDir[0] != '\0') {
        char *base = g_path_get_basename(pngPath);
        char *composed = g_strdup_printf("%s/%s", resDir, base);
        g_free(base);
        if (stat(composed, &st) == 0 && S_ISREG(st.st_mode)) {
            return composed;
        }
        g_free(composed);
    }
    return NULL;
}

// The watcher resolves an icon by theme name, so a file is exposed as a theme directory
// holding it and named by its basename without extension.
void ionInstallTrayImage(const char *pngPath) {
    ensureIndicator();
    char *resolved = resolveIconPath(pngPath);
    if (resolved == NULL) {
        app_indicator_set_icon(s_indicator, "application-x-executable", "ion-tray");
        return;
    }
    char *dir = g_path_get_dirname(resolved);
    char *base = g_path_get_basename(resolved);
    char *dot = strrchr(base, '.');
    if (dot != NULL) *dot = '\0';
    app_indicator_set_icon_theme_path(s_indicator, dir);
    app_indicator_set_icon(s_indicator, base, "ion-tray");
    g_free(dir);
    g_free(base);
    g_free(resolved);
}

void ionUninstallTray(void) {
    if (s_indicator == NULL) return;
    app_indicator_set_status(s_indicator, APP_INDICATOR_STATUS_PASSIVE);
    g_object_unref(s_indicator);
    s_indicator = NULL;
}
