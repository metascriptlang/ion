#ifndef ION_LINUX_INTERNAL_H
#define ION_LINUX_INTERNAL_H

#include <gtk/gtk.h>
#include <webkit/webkit.h>
#include "../common/strconv.h"
#include "state.h"

#ifdef __cplusplus
extern "C" {
#endif

GtkWidget *ionGetMainWindow(void);
void       ionLinuxPresentMain(void);
void       ionLinuxReleaseReadDestroyed(void);
void       ionLinuxSyncFrameState(IonLinuxWindowState *st);
double     ionLinuxScale(IonLinuxWindowState *st);

int  ionLinuxX11SetAbove(GtkWidget *window, int on);

void ionLinuxFrameSync(void);
void ionLinuxFrameDetach(IonLinuxWindowState *st);

int  ionLinuxPumpUntil(const volatile int *done, int timeoutMs);

void ionLinuxAttachInput(IonLinuxWindowState *st);
void ionLinuxDetachInput(IonLinuxWindowState *st);
void ionLinuxUpdateContentFocus(IonLinuxWindowState *st);
void ionLinuxPushResize(IonLinuxWindowState *st, int logicalW, int logicalH);

// Scheme registration latches into the WebKitWebContext: call before any view is created.
void ionInstallSchemeHandlers(WebKitWebContext *ctx);
void ionAttachMessageHandler(WebKitUserContentManager *ucm, int webview);
void ionAttachNavHandler(WebKitWebView *view);

#ifdef __cplusplus
}
#endif

#endif
