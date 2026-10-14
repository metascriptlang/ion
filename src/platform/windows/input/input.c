#include "../state.h"
#include "../internal.h"
#include "../../bridge.h"
#include "../../common/inputEvents.h"
#include "../../common/keys.h"

#include <imm.h>
#include <windowsx.h>
#include <string.h>

#define ION_TEXT_CAP 64

static int  s_tracking = 0;
static int  s_lastX = 0, s_lastY = 0;
static int  s_cursor = ION_CURSOR_ARROW;
static RECT s_imeRect;

static int            s_pendingActive = 0;
static IonInputRecord s_pending;
static char           s_pendingText[ION_TEXT_CAP];
static WCHAR          s_highSurrogate = 0;
static int            s_preeditActive = 0;

static int scancodeToKey(unsigned sc) {
    switch (sc) {
        case 0x0029: return ION_KEY_BACKQUOTE;
        case 0x002b: return ION_KEY_BACKSLASH;
        case 0x000e: return ION_KEY_BACKSPACE;
        case 0x001a: return ION_KEY_BRACKET_LEFT;
        case 0x001b: return ION_KEY_BRACKET_RIGHT;
        case 0x0033: return ION_KEY_COMMA;
        case 0x000b: return ION_KEY_DIGIT0;
        case 0x0002: return ION_KEY_DIGIT1;
        case 0x0003: return ION_KEY_DIGIT2;
        case 0x0004: return ION_KEY_DIGIT3;
        case 0x0005: return ION_KEY_DIGIT4;
        case 0x0006: return ION_KEY_DIGIT5;
        case 0x0007: return ION_KEY_DIGIT6;
        case 0x0008: return ION_KEY_DIGIT7;
        case 0x0009: return ION_KEY_DIGIT8;
        case 0x000a: return ION_KEY_DIGIT9;
        case 0x000d: return ION_KEY_EQUAL;
        case 0x0056: return ION_KEY_INTL_BACKSLASH;
        case 0x0073: return ION_KEY_INTL_RO;
        case 0x007d: return ION_KEY_INTL_YEN;
        case 0x001e: return ION_KEY_KEY_A;
        case 0x0030: return ION_KEY_KEY_B;
        case 0x002e: return ION_KEY_KEY_C;
        case 0x0020: return ION_KEY_KEY_D;
        case 0x0012: return ION_KEY_KEY_E;
        case 0x0021: return ION_KEY_KEY_F;
        case 0x0022: return ION_KEY_KEY_G;
        case 0x0023: return ION_KEY_KEY_H;
        case 0x0017: return ION_KEY_KEY_I;
        case 0x0024: return ION_KEY_KEY_J;
        case 0x0025: return ION_KEY_KEY_K;
        case 0x0026: return ION_KEY_KEY_L;
        case 0x0032: return ION_KEY_KEY_M;
        case 0x0031: return ION_KEY_KEY_N;
        case 0x0018: return ION_KEY_KEY_O;
        case 0x0019: return ION_KEY_KEY_P;
        case 0x0010: return ION_KEY_KEY_Q;
        case 0x0013: return ION_KEY_KEY_R;
        case 0x001f: return ION_KEY_KEY_S;
        case 0x0014: return ION_KEY_KEY_T;
        case 0x0016: return ION_KEY_KEY_U;
        case 0x002f: return ION_KEY_KEY_V;
        case 0x0011: return ION_KEY_KEY_W;
        case 0x002d: return ION_KEY_KEY_X;
        case 0x0015: return ION_KEY_KEY_Y;
        case 0x002c: return ION_KEY_KEY_Z;
        case 0x000c: return ION_KEY_MINUS;
        case 0x0034: return ION_KEY_PERIOD;
        case 0x0028: return ION_KEY_QUOTE;
        case 0x0027: return ION_KEY_SEMICOLON;
        case 0x0035: return ION_KEY_SLASH;
        case 0x0038: return ION_KEY_ALT_LEFT;
        case 0xe038: return ION_KEY_ALT_RIGHT;
        case 0x003a: return ION_KEY_CAPS_LOCK;
        case 0xe05d: return ION_KEY_CONTEXT_MENU;
        case 0x001d: return ION_KEY_CONTROL_LEFT;
        case 0xe01d: return ION_KEY_CONTROL_RIGHT;
        case 0x001c: return ION_KEY_ENTER;
        case 0xe05b: return ION_KEY_META_LEFT;
        case 0xe05c: return ION_KEY_META_RIGHT;
        case 0x002a: return ION_KEY_SHIFT_LEFT;
        case 0x0036: return ION_KEY_SHIFT_RIGHT;
        case 0x0039: return ION_KEY_SPACE;
        case 0x000f: return ION_KEY_TAB;
        case 0x0079: return ION_KEY_CONVERT;
        case 0x0072: case 0xe0f2: return ION_KEY_LANG1;
        case 0x0071: case 0xe0f1: return ION_KEY_LANG2;
        case 0x0078: return ION_KEY_LANG3;
        case 0x0077: return ION_KEY_LANG4;
        case 0x0070: return ION_KEY_KANA_MODE;
        case 0x007b: return ION_KEY_NON_CONVERT;
        case 0xe053: return ION_KEY_DELETE;
        case 0xe04f: return ION_KEY_END;
        case 0xe047: return ION_KEY_HOME;
        case 0xe052: return ION_KEY_INSERT;
        case 0xe051: return ION_KEY_PAGE_DOWN;
        case 0xe049: return ION_KEY_PAGE_UP;
        case 0xe050: return ION_KEY_ARROW_DOWN;
        case 0xe04b: return ION_KEY_ARROW_LEFT;
        case 0xe04d: return ION_KEY_ARROW_RIGHT;
        case 0xe048: return ION_KEY_ARROW_UP;
        case 0xe045: return ION_KEY_NUM_LOCK;
        case 0x0052: return ION_KEY_NUMPAD0;
        case 0x004f: return ION_KEY_NUMPAD1;
        case 0x0050: return ION_KEY_NUMPAD2;
        case 0x0051: return ION_KEY_NUMPAD3;
        case 0x004b: return ION_KEY_NUMPAD4;
        case 0x004c: return ION_KEY_NUMPAD5;
        case 0x004d: return ION_KEY_NUMPAD6;
        case 0x0047: return ION_KEY_NUMPAD7;
        case 0x0048: return ION_KEY_NUMPAD8;
        case 0x0049: return ION_KEY_NUMPAD9;
        case 0x004e: return ION_KEY_NUMPAD_ADD;
        case 0x007e: return ION_KEY_NUMPAD_COMMA;
        case 0x0053: return ION_KEY_NUMPAD_DECIMAL;
        case 0xe035: return ION_KEY_NUMPAD_DIVIDE;
        case 0xe01c: return ION_KEY_NUMPAD_ENTER;
        case 0x0059: return ION_KEY_NUMPAD_EQUAL;
        case 0x0037: return ION_KEY_NUMPAD_MULTIPLY;
        case 0x004a: return ION_KEY_NUMPAD_SUBTRACT;
        case 0x0001: return ION_KEY_ESCAPE;
        case 0x003b: return ION_KEY_F1;
        case 0x003c: return ION_KEY_F2;
        case 0x003d: return ION_KEY_F3;
        case 0x003e: return ION_KEY_F4;
        case 0x003f: return ION_KEY_F5;
        case 0x0040: return ION_KEY_F6;
        case 0x0041: return ION_KEY_F7;
        case 0x0042: return ION_KEY_F8;
        case 0x0043: return ION_KEY_F9;
        case 0x0044: return ION_KEY_F10;
        case 0x0057: return ION_KEY_F11;
        case 0x0058: return ION_KEY_F12;
        case 0x0064: return ION_KEY_F13;
        case 0x0065: return ION_KEY_F14;
        case 0x0066: return ION_KEY_F15;
        case 0x0067: return ION_KEY_F16;
        case 0x0068: return ION_KEY_F17;
        case 0x0069: return ION_KEY_F18;
        case 0x006a: return ION_KEY_F19;
        case 0x006b: return ION_KEY_F20;
        case 0x006c: return ION_KEY_F21;
        case 0x006d: return ION_KEY_F22;
        case 0x006e: return ION_KEY_F23;
        case 0x0076: return ION_KEY_F24;
        case 0xe037: case 0x0054: return ION_KEY_PRINT_SCREEN;
        case 0x0046: return ION_KEY_SCROLL_LOCK;
        case 0x0045: case 0xe046: return ION_KEY_PAUSE;
        case 0xe06a: return ION_KEY_BROWSER_BACK;
        case 0xe066: return ION_KEY_BROWSER_FAVORITES;
        case 0xe069: return ION_KEY_BROWSER_FORWARD;
        case 0xe032: return ION_KEY_BROWSER_HOME;
        case 0xe067: return ION_KEY_BROWSER_REFRESH;
        case 0xe065: return ION_KEY_BROWSER_SEARCH;
        case 0xe068: return ION_KEY_BROWSER_STOP;
        case 0xe06b: return ION_KEY_LAUNCH_APP1;
        case 0xe021: return ION_KEY_LAUNCH_APP2;
        case 0xe06c: return ION_KEY_LAUNCH_MAIL;
        case 0xe022: return ION_KEY_MEDIA_PLAY_PAUSE;
        case 0xe06d: return ION_KEY_MEDIA_SELECT;
        case 0xe024: return ION_KEY_MEDIA_STOP;
        case 0xe019: return ION_KEY_MEDIA_TRACK_NEXT;
        case 0xe010: return ION_KEY_MEDIA_TRACK_PREVIOUS;
        case 0xe05e: return ION_KEY_POWER;
        case 0xe02e: return ION_KEY_AUDIO_VOLUME_DOWN;
        case 0xe020: return ION_KEY_AUDIO_VOLUME_MUTE;
        case 0xe030: return ION_KEY_AUDIO_VOLUME_UP;
        case 0xe008: return ION_KEY_UNDO;
        case 0xe00a: return ION_KEY_PASTE;
        case 0xe017: return ION_KEY_CUT;
        case 0xe018: return ION_KEY_COPY;
        case 0xe02c: return ION_KEY_EJECT;
        case 0xe03b: return ION_KEY_HELP;
        case 0xe05f: return ION_KEY_SLEEP;
        case 0xe063: return ION_KEY_WAKE_UP;
        default:     return ION_KEY_UNIDENTIFIED;
    }
}

static unsigned scancodeOf(WPARAM vk, LPARAM lParam) {
    if (vk == VK_NUMLOCK) return 0xe045;
    if (vk == VK_PAUSE) return 0x0045;
    unsigned sc = (unsigned)((lParam >> 16) & 0xff);
    if (sc == 0) return MapVirtualKeyW((UINT)vk, MAPVK_VK_TO_VSC_EX);
    if (lParam & (1 << 24)) sc |= 0xe000;
    return sc;
}

static int currentMods(void) {
    int m = 0;
    if (GetKeyState(VK_SHIFT) & 0x8000)   m |= ION_MOD_SHIFT;
    if (GetKeyState(VK_RSHIFT) & 0x8000)  m |= ION_MOD_SHIFT_RIGHT;
    if (GetKeyState(VK_CONTROL) & 0x8000) m |= ION_MOD_CTRL;
    if (GetKeyState(VK_RCONTROL) & 0x8000) m |= ION_MOD_CTRL_RIGHT;
    if (GetKeyState(VK_MENU) & 0x8000)    m |= ION_MOD_ALT;
    if (GetKeyState(VK_RMENU) & 0x8000)   m |= ION_MOD_ALT_RIGHT;
    if ((GetKeyState(VK_LWIN) | GetKeyState(VK_RWIN)) & 0x8000) m |= ION_MOD_SUPER;
    if (GetKeyState(VK_RWIN) & 0x8000)    m |= ION_MOD_SUPER_RIGHT;
    if (GetKeyState(VK_CAPITAL) & 1)      m |= ION_MOD_CAPS_LOCK;
    if (GetKeyState(VK_NUMLOCK) & 1)      m |= ION_MOD_NUM_LOCK;
    return m;
}

static unsigned decodeFirst(const WCHAR *w, int n) {
    if (n <= 0) return 0;
    if (n >= 2 && IS_HIGH_SURROGATE(w[0]) && IS_LOW_SURROGATE(w[1]))
        return 0x10000u + (((unsigned)w[0] - 0xd800u) << 10) + ((unsigned)w[1] - 0xdc00u);
    return w[0];
}

// ToUnicodeEx flag 0x4 (Windows 10 1607+) leaves the dead-key state untouched,
// so probing the unshifted character cannot eat a pending dead key.
static unsigned unshiftedOf(WPARAM vk, unsigned sc) {
    BYTE state[256];
    WCHAR buf[4];
    memset(state, 0, sizeof state);
    int n = ToUnicodeEx((UINT)vk, sc, state, buf, 4, 0x4, GetKeyboardLayout(0));
    unsigned cp = decodeFirst(buf, n);
    return cp >= 0x20 && cp != 0x7f ? cp : 0;
}

static int utf16ToUtf8(const WCHAR *w, int n, char *out, int cap) {
    if (n <= 0) { if (cap > 0) out[0] = '\0'; return 0; }
    int len = WideCharToMultiByte(CP_UTF8, 0, w, n, out, cap - 1, NULL, NULL);
    out[len > 0 ? len : 0] = '\0';
    return len;
}

static void pushText(int type, int win, const char *utf8, double p1) {
    IonInputRecord r;
    memset(&r, 0, sizeof r);
    r.type = type;
    r.window = win;
    r.p1 = p1;
    r.text = utf8;
    ion_input_push_record(&r);
}

void ionWinKeyFlush(void) {
    if (!s_pendingActive) return;
    s_pendingActive = 0;
    if (s_pendingText[0] != '\0') {
        WCHAR w[4];
        int n = MultiByteToWideChar(CP_UTF8, 0, s_pendingText, -1, w, 4);
        unsigned first = decodeFirst(w, n - 1);
        if ((s_pending.mods & ION_MOD_SHIFT) && first != s_pending.unshifted)
            s_pending.consumedMods |= ION_MOD_SHIFT;
        if ((s_pending.mods & ION_MOD_CTRL) && (s_pending.mods & ION_MOD_ALT) && first >= 0x20)
            s_pending.consumedMods |= ION_MOD_CTRL | ION_MOD_ALT;
    }
    s_pending.text = s_pendingText;
    ion_input_push_record(&s_pending);
}

static void appendChar(int win, WCHAR unit) {
    WCHAR w[2];
    int n = 0;
    if (IS_HIGH_SURROGATE(unit)) { s_highSurrogate = unit; return; }
    if (IS_LOW_SURROGATE(unit) && s_highSurrogate) { w[n++] = s_highSurrogate; }
    s_highSurrogate = 0;
    w[n++] = unit;
    char utf8[8];
    int len = utf16ToUtf8(w, n, utf8, sizeof utf8);
    if (len <= 0) return;
    if (s_pendingActive) {
        size_t have = strlen(s_pendingText);
        if (have + (size_t)len < sizeof s_pendingText) memcpy(s_pendingText + have, utf8, (size_t)len + 1);
        else { ionWinKeyFlush(); pushText(ION_INPUT_TEXT, win, utf8, 0); }
    } else {
        pushText(ION_INPUT_TEXT, win, utf8, 0);
    }
}

static void keyEvent(int win, UINT msg, WPARAM vk, LPARAM lParam) {
    ionWinKeyFlush();
    unsigned sc = scancodeOf(vk, lParam);
    IonInputRecord r;
    memset(&r, 0, sizeof r);
    r.type = ION_INPUT_KEY;
    r.window = win;
    r.key = scancodeToKey(sc);
    r.scancode = (int)sc;
    r.mods = currentMods();
    r.unshifted = unshiftedOf(vk, sc);
    if (msg == WM_KEYUP || msg == WM_SYSKEYUP) {
        r.p1 = ION_KEY_RELEASE;
        ion_input_push_record(&r);
        return;
    }
    r.p1 = (lParam & (1 << 30)) ? ION_KEY_REPEAT : ION_KEY_PRESS;
    s_pending = r;
    s_pendingText[0] = '\0';
    s_pendingActive = 1;
}

static void imeReposition(void) {
    HWND hwnd = ionGetMainHwnd();
    RECT rc = s_imeRect;
    if (hwnd == NULL) return;
    HIMC himc = ImmGetContext(hwnd);
    if (himc == NULL) return;
    COMPOSITIONFORM cf;
    memset(&cf, 0, sizeof cf);
    cf.dwStyle = CFS_POINT;
    cf.ptCurrentPos.x = rc.left;
    cf.ptCurrentPos.y = rc.top;
    ImmSetCompositionWindow(himc, &cf);
    CANDIDATEFORM cand;
    memset(&cand, 0, sizeof cand);
    cand.dwIndex = 0;
    cand.dwStyle = CFS_EXCLUDE;
    cand.ptCurrentPos.x = rc.left;
    cand.ptCurrentPos.y = rc.bottom;
    cand.rcArea = rc;
    ImmSetCandidateWindow(himc, &cand);
    ImmReleaseContext(hwnd, himc);
}

static int imeString(HIMC himc, DWORD kind, char *out, int cap, WCHAR *wbuf, int wcap) {
    LONG bytes = ImmGetCompositionStringW(himc, kind, NULL, 0);
    if (bytes <= 0) { out[0] = '\0'; return 0; }
    int n = (int)(bytes / (LONG)sizeof(WCHAR));
    if (n > wcap) n = wcap;
    ImmGetCompositionStringW(himc, kind, wbuf, (DWORD)(n * (int)sizeof(WCHAR)));
    utf16ToUtf8(wbuf, n, out, cap);
    return n;
}

static void imeComposition(HWND hwnd, int win, LPARAM lParam) {
    static WCHAR wbuf[512];
    static char  utf8[2048];
    HIMC himc = ImmGetContext(hwnd);
    if (himc == NULL) return;
    if (lParam & GCS_RESULTSTR) {
        imeString(himc, GCS_RESULTSTR, utf8, sizeof utf8, wbuf, 512);
        if (s_preeditActive) { pushText(ION_INPUT_PREEDIT, win, "", 0); s_preeditActive = 0; }
        if (utf8[0] != '\0') pushText(ION_INPUT_TEXT, win, utf8, 0);
    }
    if (lParam & GCS_COMPSTR) {
        int n = imeString(himc, GCS_COMPSTR, utf8, sizeof utf8, wbuf, 512);
        LONG cursor = n;
        if (lParam & GCS_CURSORPOS) cursor = ImmGetCompositionStringW(himc, GCS_CURSORPOS, NULL, 0);
        if (cursor < 0 || cursor > n) cursor = n;
        char head[2048];
        int offset = utf16ToUtf8(wbuf, (int)cursor, head, sizeof head);
        pushText(ION_INPUT_PREEDIT, win, utf8, offset);
        s_preeditActive = utf8[0] != '\0';
    }
    if (lParam == 0 && s_preeditActive) {
        pushText(ION_INPUT_PREEDIT, win, "", 0);
        s_preeditActive = 0;
    }
    ImmReleaseContext(hwnd, himc);
}

static void pushPointer(int type, int x, int y, double p1, double p2) {
    IonInputRecord r;
    memset(&r, 0, sizeof r);
    r.type = type;
    r.window = ionGetMainWindowId();
    r.x = x;
    r.y = y;
    r.p1 = p1;
    r.p2 = p2;
    ion_input_push_record(&r);
}

static int buttonOf(UINT msg, WPARAM wParam) {
    switch (msg) {
        case WM_LBUTTONDOWN: case WM_LBUTTONUP: return 1;
        case WM_RBUTTONDOWN: case WM_RBUTTONUP: return 2;
        case WM_MBUTTONDOWN: case WM_MBUTTONUP: return 3;
        case WM_XBUTTONDOWN: case WM_XBUTTONUP: return GET_XBUTTON_WPARAM(wParam) == XBUTTON1 ? 4 : 5;
        default: return 0;
    }
}

static int isButtonDown(UINT msg) {
    return msg == WM_LBUTTONDOWN || msg == WM_RBUTTONDOWN || msg == WM_MBUTTONDOWN || msg == WM_XBUTTONDOWN;
}

static int anyButtonHeld(WPARAM wParam) {
    return (GET_KEYSTATE_WPARAM(wParam) & (MK_LBUTTON | MK_RBUTTON | MK_MBUTTON | MK_XBUTTON1 | MK_XBUTTON2)) != 0;
}

static void mouseMessage(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    POINT pt = { GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam) };
    if (msg == WM_MOUSEWHEEL || msg == WM_MOUSEHWHEEL) ScreenToClient(hwnd, &pt);

    if (msg == WM_MOUSELEAVE) {
        s_tracking = 0;
        if (GetCapture() != hwnd) pushPointer(ION_INPUT_LEAVE, s_lastX, s_lastY, 0, 0);
        return;
    }
    if (msg == WM_MOUSEMOVE && !s_tracking) {
        TRACKMOUSEEVENT tme = { sizeof tme, TME_LEAVE, hwnd, 0 };
        TrackMouseEvent(&tme);
        s_tracking = 1;
    }

    switch (msg) {
        case WM_MOUSEMOVE:
            pushPointer(ION_INPUT_MOTION, pt.x, pt.y, pt.x - s_lastX, pt.y - s_lastY);
            break;
        case WM_MOUSEWHEEL:
            pushPointer(ION_INPUT_WHEEL, pt.x, pt.y, 0, (double)GET_WHEEL_DELTA_WPARAM(wParam) / WHEEL_DELTA);
            break;
        case WM_MOUSEHWHEEL:
            pushPointer(ION_INPUT_WHEEL, pt.x, pt.y, (double)GET_WHEEL_DELTA_WPARAM(wParam) / WHEEL_DELTA, 0);
            break;
        default:
            if (isButtonDown(msg) && GetCapture() != hwnd) SetCapture(hwnd);
            pushPointer(ION_INPUT_BUTTON, pt.x, pt.y, buttonOf(msg, wParam), isButtonDown(msg));
            if (!isButtonDown(msg) && !anyButtonHeld(wParam) && GetCapture() == hwnd) ReleaseCapture();
            break;
    }
    s_lastX = pt.x;
    s_lastY = pt.y;
}

static LPCWSTR cursorShape(int cursor) {
    switch (cursor) {
        case ION_CURSOR_HAND:     return IDC_HAND;
        case ION_CURSOR_IBEAM:    return IDC_IBEAM;
        case ION_CURSOR_CROSS:    return IDC_CROSS;
        case ION_CURSOR_RESIZE_H: return IDC_SIZEWE;
        case ION_CURSOR_RESIZE_V: return IDC_SIZENS;
        default:                  return IDC_ARROW;
    }
}

void ionWinPushResize(void) {
    HWND hwnd = ionGetMainHwnd();
    if (hwnd == NULL) return;
    RECT rc;
    GetClientRect(hwnd, &rc);
    UINT dpi = GetDpiForWindow(hwnd);
    IonInputRecord r;
    memset(&r, 0, sizeof r);
    r.type = ION_INPUT_RESIZE;
    r.window = ionGetMainWindowId();
    r.x = (double)(dpi ? dpi : 96) / 96.0;
    r.p1 = rc.right - rc.left;
    r.p2 = rc.bottom - rc.top;
    ion_input_push_record(&r);
    ionWindowRequestFrame(r.window);
}

static void pushFocus(int gained) {
    IonInputRecord r;
    memset(&r, 0, sizeof r);
    r.type = ION_INPUT_FOCUS;
    r.window = ionGetMainWindowId();
    r.p1 = gained;
    ion_input_push_record(&r);
}

void ionWindowFocusContent(IonWindowId id) {
    HWND hwnd = ionWinHwnd(id);
    if (hwnd != NULL && GetFocus() != hwnd) SetFocus(hwnd);
}

void ionWindowSetImeRect(IonWindowId id, int x, int y, int w, int h) {
    if (ionWinHwnd(id) == NULL) return;
    s_imeRect.left = x;
    s_imeRect.top = y;
    s_imeRect.right = x + w;
    s_imeRect.bottom = y + h;
    if (GetFocus() == ionGetMainHwnd()) imeReposition();
}

void ionWindowSetCursor(IonWindowId id, int cursor) {
    if (ionWinHwnd(id) == NULL) return;
    s_cursor = cursor;
    if (ionWebView2LastPointerTarget() == ION_WEBVIEW_INVALID) SetCursor(LoadCursorW(NULL, cursorShape(cursor)));
}

int ionWinHandleInput(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam, LRESULT *result) {
    int win = ionGetMainWindowId();
    *result = 0;
    switch (msg) {
        case WM_MOUSEMOVE:
        case WM_LBUTTONDOWN: case WM_LBUTTONUP:
        case WM_RBUTTONDOWN: case WM_RBUTTONUP:
        case WM_MBUTTONDOWN: case WM_MBUTTONUP:
        case WM_XBUTTONDOWN: case WM_XBUTTONUP:
        case WM_MOUSEWHEEL:  case WM_MOUSEHWHEEL:
        case WM_MOUSELEAVE:
            mouseMessage(hwnd, msg, wParam, lParam);
            if (msg == WM_XBUTTONDOWN || msg == WM_XBUTTONUP) *result = TRUE;
            return 1;

        case WM_SETCURSOR: {
            if (LOWORD(lParam) != HTCLIENT) return 0;
            HCURSOR web = ionWebView2Cursor(ionWebView2LastPointerTarget());
            SetCursor(web != NULL ? web : LoadCursorW(NULL, cursorShape(s_cursor)));
            *result = TRUE;
            return 1;
        }

        case WM_SETFOCUS:
            pushFocus(1);
            return 1;
        case WM_KILLFOCUS:
            ionWinKeyFlush();
            pushFocus(0);
            return 1;

        case WM_KEYDOWN: case WM_SYSKEYDOWN:
        case WM_KEYUP:   case WM_SYSKEYUP:
            if (msg == WM_SYSKEYDOWN && wParam == VK_F4) return 0;
            if (wParam == VK_PROCESSKEY || wParam == VK_PACKET) { ionWinKeyFlush(); return 1; }
            keyEvent(win, msg, wParam, lParam);
            return 1;

        case WM_CHAR: case WM_SYSCHAR:
            appendChar(win, (WCHAR)wParam);
            return 1;
        case WM_DEADCHAR: case WM_SYSDEADCHAR:
            return 1;

        case WM_IME_SETCONTEXT:
            *result = DefWindowProcW(hwnd, msg, wParam, lParam & ~(LPARAM)ISC_SHOWUICOMPOSITIONWINDOW);
            return 1;
        case WM_IME_STARTCOMPOSITION:
            imeReposition();
            return 1;
        case WM_IME_COMPOSITION:
            imeComposition(hwnd, win, lParam);
            return 1;
        case WM_IME_ENDCOMPOSITION:
            if (s_preeditActive) { pushText(ION_INPUT_PREEDIT, win, "", 0); s_preeditActive = 0; }
            return 1;

        default:
            return 0;
    }
}
