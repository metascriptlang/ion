#include "../internal.h"

static gboolean keepWaking(gpointer data) {
    (void)data;
    return G_SOURCE_CONTINUE;
}

int ionLinuxPumpUntil(const volatile int *done, int timeoutMs) {
    gint64 deadline = timeoutMs < 0 ? G_MAXINT64 : g_get_monotonic_time() + (gint64)timeoutMs * 1000;
    guint tick = g_timeout_add(10, keepWaking, NULL);
    while (!*done && g_get_monotonic_time() < deadline) {
        g_main_context_iteration(NULL, TRUE);
    }
    g_source_remove(tick);
    return *done;
}
