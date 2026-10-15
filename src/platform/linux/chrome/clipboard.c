#include "../state.h"
#include "../internal.h"
#include "../../bridge.h"
#include "../../common/strconv.h"

#include <gtk/gtk.h>
#include <stdio.h>
#include <stdlib.h>

#define READ_TIMEOUT_MS 2000

typedef struct {
    int   done;
    int   abandoned;
    char *text;
} ReadResult;

static void onText(GObject *source, GAsyncResult *res, gpointer data) {
    ReadResult *r = (ReadResult *)data;
    r->text = gdk_clipboard_read_text_finish(GDK_CLIPBOARD(source), res, NULL);
    r->done = 1;
    if (r->abandoned) {
        g_free(r->text);
        free(r);
    }
}

static char *readLocal(GdkClipboard *board) {
    GdkContentProvider *provider = gdk_clipboard_get_content(board);
    if (provider == NULL) return NULL;
    GValue value = G_VALUE_INIT;
    g_value_init(&value, G_TYPE_STRING);
    char *text = NULL;
    if (gdk_content_provider_get_value(provider, &value, NULL)) text = g_value_dup_string(&value);
    g_value_unset(&value);
    return text;
}

msString ionClipboardRead(void) {
    GdkClipboard *board = gdk_display_get_clipboard(gdk_display_get_default());
    char *text;
    if (gdk_clipboard_is_local(board)) {
        text = readLocal(board);
    } else {
        ReadResult *r = (ReadResult *)calloc(1, sizeof *r);
        if (r == NULL) return MS_EMPTY_STRING;
        gdk_clipboard_read_text_async(board, NULL, onText, r);
        if (!ionLinuxPumpUntil(&r->done, READ_TIMEOUT_MS)) {
            fprintf(stderr, "[ion] clipboard read: no answer from the clipboard owner in %d ms\n", READ_TIMEOUT_MS);
            r->abandoned = 1;
            return MS_EMPTY_STRING;
        }
        text = r->text;
        free(r);
    }
    if (text == NULL) return MS_EMPTY_STRING;
    msString out = cStringToMs(text);
    g_free(text);
    return out;
}

int ionClipboardWrite(const char *text) {
    GdkClipboard *board = gdk_display_get_clipboard(gdk_display_get_default());
    gdk_clipboard_set_text(board, text != NULL ? text : "");
    return 1;
}
