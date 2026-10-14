// Ion Linux — text clipboard (GtkClipboard, CLIPBOARD selection).

#include "../state.h"
#include "../../bridge.h"
#include "../../common/strconv.h"

#include <gtk/gtk.h>

msString ionClipboardRead(void) {
    GtkClipboard *board = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
    gchar *text = gtk_clipboard_wait_for_text(board);
    if (text == NULL) return MS_EMPTY_STRING;
    msString out = cStringToMs(text);
    g_free(text);
    return out;
}

int ionClipboardWrite(const char *text) {
    GtkClipboard *board = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
    gtk_clipboard_set_text(board, text != NULL ? text : "", -1);
    // Hands the text to a clipboard manager so it outlives this process.
    gtk_clipboard_store(board);
    return 1;
}
