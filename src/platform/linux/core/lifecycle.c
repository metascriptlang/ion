// Ion Linux — process lifecycle: ionInit / ionQuit + deep link bootstrap.
//
// Three things happen native-side before MS user code resumes:
//   1. **Cold-start deep link** — if argv contains a `scheme://...` URL
//      (registered via .desktop MimeType=x-scheme-handler/...), stash it in
//      s_coldStartUrl. window.c replays as "deeplink" IPC after window opens.
//   2. **Single-instance** — own a session-bus name (basename of /proc/self/exe).
//      Secondary launches detect the name is taken, forward their URL via a
//      DBus method call on the primary, then exit. Mirrors Win's named-mutex
//      + WM_COPYDATA pattern; Mac gets this free via NSAppleEventManager.
//   3. **GTK init** — required before any widget creation.
//
// DBus chosen over filesystem-based locks (flock) because Flatpak isolates
// $XDG_RUNTIME_DIR per-app-instance only inconsistently across portal versions
// — the session bus is the reliable cross-sandbox channel.

#include "../state.h"
#include "../../bridge.h"
#include "../../common/queue.h"

#include <gtk/gtk.h>
#include <gio/gio.h>
#include <linux/limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int  s_initialized   = 0;
static char s_busName[256]  = {0};
static char s_objectPath[256] = {0};
static guint s_dbusNameId   = 0;
static guint s_dbusObjectId = 0;

// Derive a valid DBus bus name from /proc/self/exe basename. Bus names
// require at least one `.` and must match [A-Za-z_][A-Za-z0-9_.]*. We
// prefix with "io.ion." to guarantee shape; object path is the dotted
// name with `/` separators.
static void buildBusIdentity(void) {
    char exePath[PATH_MAX];
    ssize_t n = readlink("/proc/self/exe", exePath, sizeof(exePath) - 1);
    if (n <= 0) {
        snprintf(s_busName, sizeof(s_busName), "io.ion.app");
    } else {
        exePath[n] = '\0';
        const char *base = strrchr(exePath, '/');
        base = base ? base + 1 : exePath;
        snprintf(s_busName, sizeof(s_busName), "io.ion.%s", base);
    }
    // DBus name char-set is stricter than file paths — replace any chars
    // outside [A-Za-z0-9_.] with `_` so apps with hyphens/dots in their
    // exe name (my-app-aarch64, ion.app, etc.) still get a valid name.
    for (char *p = s_busName; *p != '\0'; p++) {
        char c = *p;
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
           || (c >= '0' && c <= '9') || c == '_' || c == '.')) {
            *p = '_';
        }
    }
    snprintf(s_objectPath, sizeof(s_objectPath), "/io/ion/app");
}

// Read /proc/self/cmdline (null-separated argv) and capture the first
// URL-shaped arg into s_coldStartUrl. We skip argv[0] (executable name).
// Buffer is ample for any realistic deep link URL.
static void captureColdStartUrl(void) {
    FILE *f = fopen("/proc/self/cmdline", "r");
    if (f == NULL) return;
    char buf[8192];
    size_t n = fread(buf, 1, sizeof(buf) - 1, f);
    fclose(f);
    if (n == 0) return;
    buf[n] = '\0';

    size_t i = 0;
    // Skip argv[0].
    while (i < n && buf[i] != '\0') i++;
    i++;
    while (i < n) {
        char *arg = &buf[i];
        size_t len = strnlen(arg, n - i);
        if (len == 0) break;
        if (strstr(arg, "://") != NULL) {
            strncpy(s_coldStartUrl, arg, sizeof(s_coldStartUrl) - 1);
            s_coldStartUrl[sizeof(s_coldStartUrl) - 1] = '\0';
            break;
        }
        i += len + 1;
    }
}

// DBus introspection XML for the single-instance interface. Minimal: one
// DeepLink(url) method secondary instances call to forward their URL.
static const gchar *kIntrospectionXml =
    "<node>"
    "  <interface name='io.ion.app'>"
    "    <method name='DeepLink'>"
    "      <arg name='url' type='s' direction='in'/>"
    "    </method>"
    "    <method name='Activate'/>"
    "  </interface>"
    "</node>";

static void handleMethodCall(GDBusConnection *conn, const gchar *sender,
                             const gchar *object_path, const gchar *interface,
                             const gchar *method_name, GVariant *parameters,
                             GDBusMethodInvocation *invocation,
                             gpointer user_data) {
    (void)conn; (void)sender; (void)object_path; (void)interface; (void)user_data;

    if (g_strcmp0(method_name, "DeepLink") == 0) {
        const gchar *url = NULL;
        g_variant_get(parameters, "(&s)", &url);
        if (url != NULL && url[0] != '\0') {
            ion_queue_push("deeplink", url);
        }
        if (s_mainWindow != NULL) {
            gtk_window_present(GTK_WINDOW(s_mainWindow));
        }
        g_dbus_method_invocation_return_value(invocation, NULL);
    } else if (g_strcmp0(method_name, "Activate") == 0) {
        if (s_mainWindow != NULL) {
            gtk_window_present(GTK_WINDOW(s_mainWindow));
        }
        g_dbus_method_invocation_return_value(invocation, NULL);
    } else {
        g_dbus_method_invocation_return_error(invocation, G_DBUS_ERROR,
            G_DBUS_ERROR_UNKNOWN_METHOD, "Unknown method '%s'", method_name);
    }
}

static const GDBusInterfaceVTable kInterfaceVtable = {
    handleMethodCall, NULL, NULL, { 0 }
};

// Try to acquire single-instance bus name. Returns 1 if we became primary
// (continue init), 0 if we were secondary (caller should exit). On bus
// errors (no session bus, headless / SSH session) we fall through as
// "primary" so the app still runs — multi-instance is degraded UX, not
// a fatal condition.
static int tryAcquireSingleInstance(void) {
    GError *err = NULL;
    GDBusConnection *conn = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, &err);
    if (conn == NULL) {
        if (err) {
            fprintf(stderr, "[ion] no session bus (multi-instance fallback): %s\n",
                    err->message);
            g_error_free(err);
        }
        return 1;
    }

    // Request our well-known name with DO_NOT_QUEUE — we either get it now
    // or someone else has it.
    GVariant *reply = g_dbus_connection_call_sync(conn,
        "org.freedesktop.DBus", "/org/freedesktop/DBus",
        "org.freedesktop.DBus", "RequestName",
        g_variant_new("(su)", s_busName, 4u /* DBUS_NAME_FLAG_DO_NOT_QUEUE */),
        G_VARIANT_TYPE("(u)"), G_DBUS_CALL_FLAGS_NONE, -1, NULL, &err);
    if (reply == NULL) {
        if (err) {
            fprintf(stderr, "[ion] RequestName failed: %s\n", err->message);
            g_error_free(err);
        }
        g_object_unref(conn);
        return 1;
    }
    guint32 ret = 0;
    g_variant_get(reply, "(u)", &ret);
    g_variant_unref(reply);

    // 1 = DBUS_REQUEST_NAME_REPLY_PRIMARY_OWNER (we got it, become primary)
    // 3 = DBUS_REQUEST_NAME_REPLY_EXISTS (taken by another process)
    if (ret == 1) {
        // Register the deep-link method handler on /io/ion/app.
        GDBusNodeInfo *node = g_dbus_node_info_new_for_xml(kIntrospectionXml, NULL);
        if (node != NULL && node->interfaces[0] != NULL) {
            s_dbusObjectId = g_dbus_connection_register_object(conn,
                s_objectPath, node->interfaces[0], &kInterfaceVtable,
                NULL, NULL, NULL);
            g_dbus_node_info_unref(node);
        }
        s_dbusNameId = (guint)ret;
        g_object_unref(conn);  // primary keeps no explicit ref — object handler retains via closure
        return 1;
    }

    // Secondary path: forward our cold-start URL (if any) to the primary,
    // then activate (raise its window), then exit. Both calls are sync;
    // primary returns immediately so we don't block long.
    if (s_coldStartUrl[0] != '\0') {
        g_dbus_connection_call_sync(conn,
            s_busName, s_objectPath, "io.ion.app", "DeepLink",
            g_variant_new("(s)", s_coldStartUrl),
            NULL, G_DBUS_CALL_FLAGS_NONE, -1, NULL, NULL);
    }
    g_dbus_connection_call_sync(conn,
        s_busName, s_objectPath, "io.ion.app", "Activate",
        NULL, NULL, G_DBUS_CALL_FLAGS_NONE, -1, NULL, NULL);
    g_object_unref(conn);
    return 0;
}

int ionInit(void) {
    if (s_initialized) return 1;

    buildBusIdentity();
    captureColdStartUrl();

    if (!tryAcquireSingleInstance()) {
        // Secondary instance — URL forwarded, exit cleanly. exit() flushes
        // stdio + runs atexit handlers; sufficient for transient launch.
        exit(0);
    }

    // gtk_init_check returns FALSE if X11/Wayland display unavailable
    // (headless / SSH without X forwarding). Caller can react via return 0.
    if (!gtk_init_check(NULL, NULL)) return 0;
    s_initialized = 1;
    return 1;
}

void ionQuit(void) {
    // gtk_main_quit was already called when the window was destroyed
    // (see core/window.c on_destroy). DBus object unregister happens
    // implicitly when the bus connection is dropped at process exit.
}
