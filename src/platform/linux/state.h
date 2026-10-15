// Ion Linux — shared state + helper declarations.
//
// Mirrors macos/state.h + windows/state.h: globals live in state.c, other
// implementation files reach them via these extern declarations.

#ifndef ION_LINUX_STATE_H
#define ION_LINUX_STATE_H

#include <gtk/gtk.h>
#include <webkit/webkit.h>

#include "../common/windowRegistry.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    IonWindowId   id;
    GtkWidget    *window;          // GtkWindow
    GtkWidget    *root;            // GtkFixed filling the window; ionWindowRoot
    GtkIMContext *im;
    int           iconified;
    int           wantAbove;       // ionSetWindowAlwaysOnTop, applied once the surface is mapped
    int           contentFocused;  // last focus record pushed
    int           clientW, clientH;
    int           wantW, wantH;    // requested client size, until the decorations around it are measured
    int           pointerKnown;
    double        lastX, lastY;
} IonLinuxWindowState;

typedef struct {
    WebKitWebView *view;   // holds one reference of its own (g_object_ref_sink)
    int            x, y;   // last ionWebviewSetBounds, device pixels
} IonLinuxWebviewState;

IonLinuxWindowState *ionLinuxWindowState(IonWindowId id);

extern GtkWidget *s_mainWindow;

// Cold-start deep link URL extracted from /proc/self/cmdline at ionInit time.
// Empty when the app was not launched with a URL arg.
extern char s_coldStartUrl[2048];

void ionEnqueueMessage(const char *name, const char *payload);

#ifdef __cplusplus
}
#endif

#endif
