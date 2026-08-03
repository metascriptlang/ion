// Ion Linux — tray (status notifier item) via libayatana-appindicator3.
//
// Modern Linux trays speak the KStatusNotifierItem (StatusNotifierItem) DBus
// protocol — supported by GNOME (via TopIcons / AppIndicator Support ext),
// KDE, Cinnamon, XFCE, Budgie, and most Wayland compositor tray plugins.
// libayatana-appindicator3 is the maintained fork of libappindicator (the
// Ubuntu original); it is the de-facto cross-distro tray API.
//
// Constraint: AppIndicator has NO direct "left-click" signal — left-click on
// the indicator surfaces the attached menu, and individual menu items emit
// "activate". To match the Mac tray.click contract (single click → IPC +
// raise window), we attach a one-item menu "Open" whose activation fires
// `tray.click`. Right-click yields the same menu (also fires the item).
//
// Icon path resolution mirrors Mac/Win: try the literal path first; fall back
// to <ionResourcePath()>/<basename>; fall back to a stock icon so the tray
// stays visible rather than vanishing on bad input.

#include "../state.h"
#include "../internal.h"
#include "../../bridge.h"

#include <libayatana-appindicator/app-indicator.h>
#include <gtk/gtk.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

static AppIndicator *s_indicator    = NULL;
static GtkWidget    *s_indicatorMenu = NULL;

static void onMenuOpenActivate(GtkMenuItem *item, gpointer user_data) {
    (void)item; (void)user_data;
    ionEnqueueMessage("tray.click", "");
    if (s_mainWindow != NULL) {
        gtk_window_present(GTK_WINDOW(s_mainWindow));
    }
}

static void ensureIndicator(void) {
    if (s_indicator != NULL) return;

    // ID must be stable for the daemon to track us across runs. Use the same
    // string for category param's logical name; Linux apps usually scope
    // it by reverse-DNS but ion is generic — caller's branding lives in
    // installTrayImage's icon.
    s_indicator = app_indicator_new(
        "ion-tray",
        "application-x-executable",  // stock fallback icon name
        APP_INDICATOR_CATEGORY_APPLICATION_STATUS);
    app_indicator_set_status(s_indicator, APP_INDICATOR_STATUS_ACTIVE);

    s_indicatorMenu = gtk_menu_new();
    GtkWidget *openItem = gtk_menu_item_new_with_label("Open");
    g_signal_connect(openItem, "activate", G_CALLBACK(onMenuOpenActivate), NULL);
    gtk_menu_shell_append(GTK_MENU_SHELL(s_indicatorMenu), openItem);
    gtk_widget_show_all(s_indicatorMenu);
    app_indicator_set_menu(s_indicator, GTK_MENU(s_indicatorMenu));
}

void ionInstallTray(const char *title) {
    ensureIndicator();
    // Label rides next to the icon on indicator-aware DEs. Falls through on
    // GNOME (label hidden by ext, icon-only).
    app_indicator_set_label(s_indicator,
                            (title != NULL && title[0] != '\0') ? title : "ion",
                            "");
}

// Resolve a (possibly relative) icon path against ionResourcePath() basenames.
// Returns a freshly allocated string the caller must g_free, or NULL.
static char *resolveIconPath(const char *pngPath) {
    if (pngPath == NULL || pngPath[0] == '\0') return NULL;

    struct stat st;
    if (stat(pngPath, &st) == 0 && S_ISREG(st.st_mode)) {
        return g_strdup(pngPath);
    }

    const char *resDir = msStringToCString(ionResourcePath());
    if (resDir != NULL && resDir[0] != '\0') {
        const char *base = pngPath;
        for (const char *p = pngPath; *p != '\0'; p++) {
            if (*p == '/') base = p + 1;
        }
        char *composed = g_strdup_printf("%s/%s", resDir, base);
        if (stat(composed, &st) == 0 && S_ISREG(st.st_mode)) {
            return composed;
        }
        g_free(composed);
    }
    return NULL;
}

void ionInstallTrayImage(const char *pngPath) {
    ensureIndicator();
    char *resolved = resolveIconPath(pngPath);
    if (resolved != NULL) {
        // set_icon_full uses an absolute filesystem path (not just an icon
        // name) when the string starts with '/'. Description is for a11y.
        app_indicator_set_icon_full(s_indicator, resolved, "ion-tray");
        g_free(resolved);
    } else {
        // Fall back to a stock icon — keeps the indicator visible.
        app_indicator_set_icon_full(s_indicator,
                                    "application-x-executable", "ion-tray");
    }
}

void ionUninstallTray(void) {
    if (s_indicator != NULL) {
        app_indicator_set_status(s_indicator, APP_INDICATOR_STATUS_PASSIVE);
        g_object_unref(s_indicator);
        s_indicator = NULL;
    }
    if (s_indicatorMenu != NULL) {
        gtk_widget_destroy(s_indicatorMenu);
        s_indicatorMenu = NULL;
    }
}
