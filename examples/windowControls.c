#include "windowControls.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <string.h>

HWND ionGetMainHwnd(void);

static int clientOrigin(int axis) {
    POINT p = {0, 0};
    ClientToScreen(ionGetMainHwnd(), &p);
    return axis == 0 ? p.x : p.y;
}

static int clientSize(int axis) {
    RECT r = {0};
    GetClientRect(ionGetMainHwnd(), &r);
    return axis == 0 ? r.right : r.bottom;
}

static int outerOrigin(int axis) {
    RECT r = {0};
    GetWindowRect(ionGetMainHwnd(), &r);
    return axis == 0 ? r.left : r.top;
}

static LONG_PTR windowLong(int index) {
    return GetWindowLongPtrW(ionGetMainHwnd(), index);
}

int wcClientX(void) { return clientOrigin(0); }
int wcClientY(void) { return clientOrigin(1); }
int wcClientW(void) { return clientSize(0); }
int wcClientH(void) { return clientSize(1); }
int wcOuterX(void) { return outerOrigin(0); }
int wcOuterY(void) { return outerOrigin(1); }
int wcDpi(void) { return (int)GetDpiForWindow(ionGetMainHwnd()); }
int wcScale(int dip) { return MulDiv(dip, wcDpi(), 96); }
int wcHasCaption(void) { return (windowLong(GWL_STYLE) & WS_CAPTION) == WS_CAPTION; }
int wcHasThickFrame(void) { return (windowLong(GWL_STYLE) & WS_THICKFRAME) != 0; }
int wcTopmost(void) { return (windowLong(GWL_EXSTYLE) & WS_EX_TOPMOST) != 0; }
int wcVisible(void) { return IsWindowVisible(ionGetMainHwnd()) != 0; }
int wcIconic(void) { return IsIconic(ionGetMainHwnd()) != 0; }
int wcZoomed(void) { return IsZoomed(ionGetMainHwnd()) != 0; }
int wcForeground(void) { return GetForegroundWindow() == ionGetMainHwnd(); }

void wcUserClose(void) { PostMessageW(ionGetMainHwnd(), WM_CLOSE, 0, 0); }

int wcTitleIs(const char *utf8) {
    wchar_t want[256], got[256];
    if (MultiByteToWideChar(CP_UTF8, 0, utf8, -1, want, 256) == 0) return 0;
    if (GetWindowTextW(ionGetMainHwnd(), got, 256) == 0) return 0;
    return wcscmp(want, got) == 0;
}
