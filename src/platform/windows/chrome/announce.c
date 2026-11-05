// Ion Windows — screen reader announcement, a UIA notification raised on the active window's
// host provider; Ion serves no UIA provider of its own for the window (TODO.md).

#include "../../bridge.h"
#include "../utf8.h"

#define COBJMACROS
#include <windows.h>
#include <uiautomation.h>

#include <stdlib.h>

int ionAnnounce(const char *text) {
    HWND hwnd = GetActiveWindow();
    if (hwnd == NULL) return ION_SERVICE_NO_WINDOW;
    wchar_t *wide = ionUtf8ToWide(text);
    if (wide == NULL) return ION_SERVICE_REFUSED;
    BSTR display = SysAllocString(wide);
    BSTR activity = SysAllocString(L"ion.announce");
    free(wide);

    IRawElementProviderSimple *provider = NULL;
    HRESULT hr = UiaHostProviderFromHwnd(hwnd, &provider);
    if (SUCCEEDED(hr)) {
        hr = UiaRaiseNotificationEvent(provider, NotificationKind_Other, NotificationProcessing_ImportantMostRecent,
                                       display, activity);
        IRawElementProviderSimple_Release(provider);
    }
    SysFreeString(display);
    SysFreeString(activity);
    return SUCCEEDED(hr) ? ION_SERVICE_DONE : ION_SERVICE_REFUSED;
}
