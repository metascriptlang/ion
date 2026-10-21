# ion — TODO / Recovery notes

State as of 2026-08-03. Rewritten after a full source probe — the previous
version (2026-05-18) had drifted badly from what's actually on disk.

> **How to read this file**: "on disk" means the code exists and is wired into
> the build. It does **not** mean re-verified today. The last recorded
> end-to-end verification for Windows and Linux was in a Parallels VM around
> 2026-05-18/19. Anything marked ⚠️ is a claim in the docs that the source
> contradicts.

## Capability matrix (verified by source inspection)

| Capability | macOS | Windows | Linux | Native impl |
|---|---|---|---|---|
| Empty window, compositor root (`windowRoot`, `windowDevice`) | ✅ measured 2026-10-18 on macOS 26.6 (Retina scale 2, 120 Hz), msc v0.3.4 `3e645dc4c`: `examples/contentInputMacos.ms`; `windowRoot` is the window's contentView (SDL's, not flipped), `windowDevice` NULL, `commit` a no-op; the resize record says 2200x1280 scale 2 for a 1100x640 window | ✅ | ✅ measured 2026-10-16 in WSL Ubuntu on WSLg (Wayland), gtk4 4.22.4: `examples/nativeContent.ms` opens a window and logs `host resize: 1100x640 scale 1` and `host focus: true` | DirectComposition on a D2D device / contentView / GtkFixed |
| Webview as a component (`createWebview`, node, bounds, IPC by label) | ✅ measured 2026-10-18 on macOS 26.6 (Retina scale 2, 120 Hz), msc v0.3.4 `3e645dc4c`: `contentInputMacos` places a WKWebView at (480,24) 560x520 px between two native views; a click at (700,260) reaches the page at 110,118 CSS px and makes it first responder, a key then reaches the page and not the content. A native view over the webview takes the click only when it handles `mouseDown` (`ContentPanel` in `examples/content/contentMac.m`): with a plain NSView the page received the click. IPC of the `.app` smoke test passes | ✅ | ✅ measured 2026-10-16 in WSL Ubuntu on WSLg (Wayland), gtk4 4.22.4: `helloWebview` loads `ion://localhost/hello.html`; the child of `nativeContent` is only started, not looked at | WebView2 composition controller per webview / WKWebView / WebKitGTK |
| IPC + `command()` | ✅ measured 2026-10-18 on macOS 26.6: the `.app` smoke test (`helloWebview`) prints `auto-probe: ipc alive`, `MS command addNumbers(100, 23)` and `[ion] IPC rejected: invalid invoke_key` | ✅ | ✅ measured 2026-10-16 in WSL Ubuntu on WSLg (Wayland), gtk4 4.22.4: `helloWebview` logs `auto-probe: ipc alive`, `MS ← ping: autoprobe`, `MS command addNumbers(100, 23)`, `[ion] IPC rejected: invalid invoke_key`, `auto-call addNumbers result: 123` | `webview/messaging` + `eval` |
| Custom URI scheme (`ion://`, `asset://`) | ✅ `ion://` measured 2026-10-18 on macOS 26.6: the `.app` smoke test loads `ion://localhost/hello.html` from the bundle and its page answers IPC. `asset://` measured 2026-10-19 on macOS 26.6, msc v0.3.4 `212a678c2`, `examples/chromeMacos.ms` with `CHROME_ASSET_ROOT`: a `fetch` from the page reads a file under the scope as 200 with its text and `/etc/hosts` as 403; `examples/assetScope.ms` does the same from an `ion://` page. Until 2026-10-19 no platform installed the `asset` scheme on its webview (`protoReg.c` listed static protocols only; `test/common/protoReg.ms` pins it) | ✅ `ion://`; `asset://` measured 2026-10-19 on Windows 11 with `examples/assetScope.ms` (msc v0.3.4 `8a9fc02dd`, run in the signed-in session): from an `ion://` page a `fetch` of `asset://localhost/C:/…/asset.txt` under the scope reads 200 with its text and `C:/Windows/System32/drivers/etc/hosts` reads 403. It needed two fixes: `protoReg.c` drops the slash before a drive letter and matches either separator, and the scheme registration allows every origin (`GetAllowedOrigins` was empty, so WebView2 refused the fetch before Ion saw it; measured by reverting it). From a `data:` page WebView2 still refuses the fetch | ✅ measured 2026-10-16 in WSL Ubuntu on WSLg (Wayland), gtk4 4.22.4: `ion://` served `hello.html` to `helloWebview`. `asset://` measured 2026-10-19 the same way (msc build `0f8278bc`, webkitgtk 2.52.6) with `examples/assetScope.ms`: from an `ion://` page a file under `/mnt/c/…` reads 200 with its text and `/etc/hosts` reads 403 | `webview/protocol.{m,cpp,c}` |
| External-link routing | ✅ measured 2026-10-19 on macOS 26.6, msc v0.3.4 `212a678c2`, `examples/chromeMacos.ms` in a bundle (`make-app.sh --url-scheme=ionchrome --sign`): a link to `http://<LAN address>:8765/ion-link` clicked in the page leaves the page on its own URL, opens the default browser, and the local server logs the `GET` | ✅ | ✍️ `ionOpenExternal` (`xdg-open`), syntax-checked, not run | `common/navpolicy.c` + per-platform nav |
| Tray | ✅ measured 2026-10-19 on macOS 26.6, msc v0.3.4 `212a678c2`, `examples/chromeMacos.ms` in a bundle (`make-app.sh --url-scheme=ionchrome --sign`): the text item is visible in the status bar, and a click (`performClick`) delivers `tray.click`. With `CHROME_PERSON=1` the app hides itself and a person's click delivers `tray.click`, activates the app and makes its window key; after a synthetic click the app was active in 2 of 4 runs | ✅ | ⚠️ `ayatana-appindicator-glib`: menu item "Open" and middle-click fire `tray.click`. WSLg 2026-10-16: no StatusNotifierWatcher on the session bus, so no icon can show; `installTray` prints `[ion] installTray: no StatusNotifierWatcher on the session bus, so no tray host shows the icon; it appears if a host starts later` on stderr and does not crash (`examples/chromeLinux.ms`). Not seen on a desktop with a host | NSStatusItem / Shell_NotifyIcon / AppIndicator |
| Notifications | ✅ measured 2026-10-19 on macOS 26.6, msc v0.3.4 `212a678c2`, `examples/chromeMacos.ms` in a bundle (`make-app.sh --url-scheme=ionchrome --sign`): authorization is asked on the first `notify` (a banner with Options, Allow); once allowed (status 2) `chrome-1` and `chrome-2` are in Notification Center. With `CHROME_PERSON=1` a person's click on `chrome-2` in Notification Center delivers `notification.click` with its id; no banner showed in the screenshot, so a click on the banner itself is not measured | ✅ | ⚠️ libnotify. WSLg 2026-10-16: no `org.freedesktop.Notifications` owner or activatable name on the session bus, so nothing can show; `notify` prints `[ion] notify: GDBus.Error:org.freedesktop.DBus.Error.ServiceUnknown: The name org.freedesktop.Notifications was not provided by any .service files` on stderr and does not crash (`examples/chromeLinux.ms`). Not seen on a desktop with a daemon | UNUserNotification / balloon / libnotify |
| File dialog | ✅ measured 2026-10-19 on macOS 26.6, msc v0.3.4 `212a678c2`, `examples/chromeMacos.ms` in a bundle (`make-app.sh --url-scheme=ionchrome --sign`): `fileOpen` runs an `NSOpenPanel`; cancelled after 1.5 s it returns `''` (1579-1584 ms). With `CHROME_PERSON=1` a person picks a file and it returns its absolute path (`/Users/le/Documents/Ghostty.icns` after 4338 ms) | ✅ | ⚠️ `GtkFileDialog` made synchronous by `ionLinuxPumpUntil`. WSLg 2026-10-16: the request goes to xdg-desktop-portal (FileChooser v4), which starts `xdg-desktop-portal-gtk`. The same `GtkFileDialog` cancelled through a `GCancellable` after 1 s returns "Cancelled by application" cleanly. Ion own `fileOpen` has no cancel hook, so its return was not observed (a person must answer; killed after 15 s in `chromeLinux`) | NSOpenPanel / IFileOpenDialog / GtkFileChooser |
| Global hotkey | ✅ measured 2026-10-19 on macOS 26.6, msc v0.3.4 `212a678c2`, `examples/chromeMacos.ms` in a bundle (`make-app.sh --url-scheme=ionchrome --sign`): Ctrl+Option+Cmd+H registers (`Ok`) and a press arrives as `hotkey` `7` while the app is frontmost. With `CHROME_PERSON=1` the app hides itself and a person's left-hand Ctrl+Option+Cmd+H arrives while it is not active | ✅ | ⚠️ X11 only (`XGrabKey` on a second X connection). Wayland: `registerHotkey` prints `[ion] registerHotkey: unavailable on Wayland, a client cannot grab a key globally; rerun with GDK_BACKEND=x11` and returns -1 (measured on WSLg). The X11 path is not run. Portal GlobalShortcuts not done | Carbon / RegisterHotKey / XGrabKey (X11) |
| Content protection | ✅ measured 2026-10-19 on macOS 26.6, msc v0.3.4 `212a678c2`, `examples/chromeMacos.ms` in a bundle (`make-app.sh --url-scheme=ionchrome --sign`): `setWindowContentProtected` gives `sharingType` 0, and `screencapture -l` of the window then fails with `could not create image from window` (it captured the window with protection off) | ✅ | ✅ | `security/content_protect.*` |
| Keychain / secrets | ✅ re-measured 2026-10-18 on macOS 26.6 (Retina scale 2, 120 Hz), msc v0.3.4 `3e645dc4c`: `examples/keychainTest.ms` set, get, delete, empty get. Its build directives moved to `keychain.ms` the same day: a keychain-only program failed to link (`_ionKeychainSet` undefined) while they lived in `ipc.ms`; its Windows cross-build links, Linux is not built | ✅ | ✍️ libsecret, unchanged, syntax-checked, not run | Keychain / CredWriteW (advapi32) / libsecret |
| `openExternal` | ✅ measured 2026-10-19 on macOS 26.6, msc v0.3.4 `212a678c2`, `examples/chromeMacos.ms` in a bundle (`make-app.sh --url-scheme=ionchrome --sign`): `openExternal("ionchrome://probe/open")` goes through LaunchServices back to the app as `deeplink` | ✅ | ✅ | `core/shell.{m,c}` |
| Multi-window | ✅ re-measured 2026-10-18 on macOS 26.6 (Retina scale 2, 120 Hz), msc v0.3.4 `3e645dc4c`: `examples/multiWindowMacos.ms` closes one of two windows through `performClose:`; the loop and the other window keep running, the loop ends after the last destroyed event | ✅ measured 2026-10-16: two windows, each with its own content, webview, input records and IPC; closing one leaves the other running, the loop ends with the last | ✅ | `common/windowRegistry.c` + `windowEvents.c`; Windows `examples/multiWindow.ms` |
| `show` | ✅ measured 2026-10-18 on macOS 26.6 (Retina scale 2, 120 Hz), msc v0.3.4 `3e645dc4c`: `examples/windowControlsMacos.ms` reads it back through AppKit: `isVisible` after hide and show | ✅ measured 2026-10-15 (`ShowWindow SW_SHOW`) | ✅ measured 2026-10-16 on WSLg (Wayland), gtk4 4.22.4, `examples/windowControlsLinux.ms`: hidden then `present` gives visible and mapped (`gtk_widget_get_visible`, `get_mapped`). The window was not focused again after the hide: `is-active` stayed 0 for the rest of the run | `core/window.{m,c}`; `examples/windowControls.ms` on Windows |
| `hide` | ✅ measured 2026-10-18 on macOS 26.6 (Retina scale 2, 120 Hz), msc v0.3.4 `3e645dc4c`: `examples/windowControlsMacos.ms` reads it back through AppKit: `isVisible` false | ✅ measured 2026-10-15 (`SW_HIDE`) | ✅ measured 2026-10-16 on WSLg (Wayland), gtk4 4.22.4, `examples/windowControlsLinux.ms`: `gtk_widget_get_visible` false, blurred event received | same |
| `focus` | ✅ measured 2026-10-18 on macOS 26.6 (Retina scale 2, 120 Hz), msc v0.3.4 `3e645dc4c`: `examples/windowControlsMacos.ms` reads it back through AppKit: from minimized it is restored, key, and the focused event arrives. `makeKeyAndOrderFront` alone never made the window of an app started from a terminal key; Ion now also activates the app (`activateIgnoringOtherApps`) | ✅ measured 2026-10-15 (`SetForegroundWindow`, Alt-key fallback after winit `window.rs:1832`); a window another app keeps in front cannot be forced | ✍️ `gtk_window_present`, not read back: the compositor gives focus (the created window was active at once; after a hide and show it was not) | same |
| `minimize` | ✅ measured 2026-10-18 on macOS 26.6 (Retina scale 2, 120 Hz), msc v0.3.4 `3e645dc4c`: `examples/windowControlsMacos.ms` reads it back through AppKit: `isMiniaturized` | ✅ measured 2026-10-15 (`SW_MINIMIZE`) | ⚠️ not observable on Wayland: `gtk_window_minimize` is called, but xdg-shell has no minimized state and GDK never sets `GDK_TOPLEVEL_STATE_MINIMIZED` (measured on WSLg: SKIP in `windowControlsLinux`). X11 not run | same |
| `maximize` | ✅ measured 2026-10-18 on macOS 26.6 (Retina scale 2, 120 Hz), msc v0.3.4 `3e645dc4c`: `examples/windowControlsMacos.ms` reads it back through AppKit: `isZoomed`, with a resized event | ✅ measured 2026-10-15 (`SW_MAXIMIZE`) | ✅ measured 2026-10-16 on WSLg (Wayland), gtk4 4.22.4, `examples/windowControlsLinux.ms`: `gtk_window_is_maximized` and `GDK_TOPLEVEL_STATE_MAXIMIZED` set, resized event received, client 3440x1353. `setSize` while maximized leaves the window maximized (Windows restores it); by the source the size stays pending until the window is unmaximized (not run) | same |
| `setTitle` | ✅ measured 2026-10-18 on macOS 26.6 (Retina scale 2, 120 Hz), msc v0.3.4 `3e645dc4c`: `examples/windowControlsMacos.ms` reads it back through AppKit: `Ion é中文 controls` read back | ✅ measured 2026-10-15 (UTF-8 to UTF-16, `é中文` read back) | ✅ measured 2026-10-16 on WSLg (Wayland), gtk4 4.22.4, `examples/windowControlsLinux.ms`: `gtk_window_get_title` equals `Ion é中文 controls` | same |
| `setSize` and `createWindow` size (client area, device-independent pixels) | ✅ measured 2026-10-18 on macOS 26.6 (Retina scale 2, 120 Hz), msc v0.3.4 `3e645dc4c`: `examples/windowControlsMacos.ms` reads it back through AppKit: content view 640x360 at create, 800x450 after `setSize`, 640x360 from a maximized window (Ion restores it first; SDL kept it maximized at 1800x1097). Points; one scale (2) | ✅ measured 2026-10-15 at 96 dpi: client rect equals the size asked, decorated or not, also from a maximized window. 144 dpi not run: one 96 dpi monitor | ✅ measured 2026-10-16 in WSL Ubuntu on WSLg (Wayland), gtk4 4.22.4: GTK counts the titlebar in the default size, so Ion adds the measured decoration size once the window is laid out; `nativeContent` asked 1100x640 and logged 1100x601 (transient) then 1100x640. Scale 1 only. Re-measured with `windowControlsLinux`: 640x360 at create, 800x450 after `setSize`, read from the compositor root | `AdjustWindowRectExForDpi` (winit `window_state.rs:507`) |
| `setPosition` (outer frame top-left, virtual-screen pixels) | ✅ measured 2026-10-18 on macOS 26.6 (Retina scale 2, 120 Hz), msc v0.3.4 `3e645dc4c`: `examples/windowControlsMacos.ms` reads it back through AppKit: outer top-left 120,90 in points from the primary screen's top-left, with a moved event, through `setFrameTopLeftPoint`. The SDL path did not move: `SDL_GetWindowBordersSize` is unsupported on Cocoa (`That operation is not supported` on stderr) | ✅ measured 2026-10-15 (`GetWindowRect` equals the point) | ⚠️ unavailable: GTK4 has no `gtk_window_move` and Wayland gives clients no global position; prints "setPosition: unavailable" and returns (measured on WSLg: the message is on stderr, `windowControlsLinux` asserts it) | winit `window.rs:560` |
| `setAlwaysOnTop` | ✅ measured 2026-10-18 on macOS 26.6 (Retina scale 2, 120 Hz), msc v0.3.4 `3e645dc4c`: `examples/windowControlsMacos.ms` reads it back through AppKit: window level above normal, then normal again | ✅ measured 2026-10-15 (`WS_EX_TOPMOST` set and cleared) | ⚠️ X11 only (`_NET_WM_STATE_ABOVE`); Wayland prints "setAlwaysOnTop: unavailable" and returns (measured on WSLg, true and false: `windowControlsLinux` asserts the message). X11 not run | `HWND_TOPMOST` / `HWND_NOTOPMOST` (winit `window_state.rs:405`) |
| `setDecorations` | ✅ measured 2026-10-18 on macOS 26.6 (Retina scale 2, 120 Hz), msc v0.3.4 `3e645dc4c`: `examples/windowControlsMacos.ms` reads it back through AppKit: titled style mask off and on, client stays 800x450 | ✅ measured 2026-10-15 (`WS_CAPTION` set and cleared; client size and origin unchanged) | ✅ measured 2026-10-16 on WSLg (Wayland), gtk4 4.22.4, `examples/windowControlsLinux.ms`: `gtk_window_get_decorated` flips; client size stays 800x450 both ways (fixed 2026-10-16: GTK keeps the toplevel size, so the client area changed by the title bar before) | `WS_OVERLAPPEDWINDOW` or `WS_POPUP` + `SWP_FRAMECHANGED` |
| Event `focused` / `blurred` | ✅ focused measured 2026-10-18 on macOS 26.6 (Retina scale 2, 120 Hz), msc v0.3.4 `3e645dc4c` (`windowControlsMacos`, after `focus`); blurred measured on build `212a678c2` when the key window is minimized | ✅ measured 2026-10-15 (`WM_ACTIVATE`) | ✅ measured 2026-10-16 on WSLg: `focused` at create, `blurred` when the window is hidden (`windowControlsLinux`) (`notify::is-active`) | `common/windowEvents.c` queue, `ionPollEvent` returns 3 |
| Event `resized` / `moved` | ✅ measured 2026-10-18 on macOS 26.6 (Retina scale 2, 120 Hz), msc v0.3.4 `3e645dc4c` (`windowControlsMacos`: setSize, setPosition, maximize) | ✅ measured 2026-10-15 (`WM_SIZE`, `WM_MOVE`; no `moved` while minimized) | ⚠️ `resized` measured 2026-10-16 on WSLg (pushed on create, `setSize`, decorations and maximize, from the probe `resize` signal); `moved` is never pushed (GTK4 reports no position) | same |
| Event `close-requested` | ✅ measured 2026-10-18 on macOS 26.6 (Retina scale 2, 120 Hz), msc v0.3.4 `3e645dc4c`: pushed from SDL's close request (`performClose:`, the title-bar button's path), then that window is destroyed; the loop ends once no window is left (`multiWindowMacos`). No veto. Cmd+Q measured on build `212a678c2` (`examples/quitMacos.ms`): `runLoop` returns 33 ms after it, a resize queued before it is delivered first, and a timer due later does not fire. Until then a close quit the app | ✅ measured 2026-10-15: pushed from `WM_CLOSE` (title-bar close), then that window is destroyed; the loop ends once no window is left (measured 2026-10-16 with two windows). No veto | ✅ measured 2026-10-16 on WSLg: `examples/multiWindowLinux.ms` closes a window through `gtk_window_close` (the `close-request` path of the titlebar button); closing one of two windows leaves the loop and the other window running, and the loop ends only after the last window's destroyed event was delivered. No veto | `docs/MULTI-WINDOW.md` lists close interception as open |
| Event `destroyed` | ✅ measured 2026-10-18 on macOS 26.6 (Retina scale 2, 120 Hz), msc v0.3.4 `3e645dc4c`: pushed for each closed window, close-requested first; the registry slot is freed once the loop has read the event | ✅ measured 2026-10-15: pushed from `WM_DESTROY` (also for `closeWindow`); the loop delivers it before quitting | ✅ measured 2026-10-16 on WSLg (`multiWindowLinux`): pushed for each closed window, close-requested first; the registry slot is freed once the loop has read the event | same |
| Native menu bar | ✅ the app menu (Quit, Edit, Window). `setAppMenu` (standard items, app items with a key) replaces it, and an app item delivers `menu.click` with its id: measured 2026-10-20 on macOS 26.6, msc v0.3.4 `733aafe43`, with `examples/menuMacos.ms` (Cmd+W posted to the app's queue). The default bar closes the key window; an app item on Cmd+W delivers `menu.click close_window` and the window stays open, with the bar declared before the first window or after it; a bar with an unknown key is refused by name and the old one stays; the `CloseWindow` item closes again | not planned: the app draws its menu in its own content (decided 2026-10-16); `setAppMenu` returns an error (cross-build links, not run) | not planned: same; not built | `macos/chrome/menu.m`; `common/noMenu.c` |
| System font lookup (`findSystemFont`) | ✅ measured 2026-10-22 on macOS 26.6, msc v0.3.4 `d64faf905`, `test/font.ms`: from Menlo, U+23F5 and U+23FA in text presentation give `STIXTwoMath.otf`, U+23FA in emoji presentation `Apple Color Emoji.ttc`, `A` `Menlo.ttc` face 0 and bold face 1; an unassigned, surrogate or out-of-range codepoint gives `null`. `CTFontCreateForString` over the character alone (a U+FE0E in the covered range moved `A` to Monaco), Apple Color Emoji first for emoji presentation | ⛔ stub: returns `null` (DirectWrite `IDWriteFontFallback::MapCharacters` not written) | ⛔ stub: returns `null` (fontconfig `FcFontSort` with a charset not written) | `macos/core/font.m`; `common/noFont.c` |
| Single instance, opt-in (`requestSingleInstance`) | ✍️ always `true`, LaunchServices keeps one instance per bundle; written, not compiled on this host | ✅ measured 2026-10-19 on Windows 11 with `examples/singleInstance.ms`, msc v0.3.4 (`~/.metascript/BUILD` `8a9fc02dd`): without the call two processes ran at once, each seeing its URL as a cold-start `deeplink`; with `--single` the second got `false` and exited 0, and the first received its own and the forwarded `deeplink`. Raise of the primary not observed | ✅ measured 2026-10-19 in WSL Ubuntu on WSLg, msc v0.3.3 (BUILD `0f8278bc`), session bus present: same two runs, same result. Raise not observed | Windows named mutex `Local\Ion-SingleInstance-<exe>` + `WM_COPYDATA`; Linux session-bus name `io.ion.<exe>` with `DeepLink` / `Activate`; `ionInit` takes neither |
| Title bar follows the system light/dark theme | ✍️ AppKit follows the system appearance by default; not measured | ✅ measured 2026-10-18 with the system in dark mode: `helloWebview`'s title bar pixel is RGB 32,32,32 (243,243,243 on the build before); `DWMWA_USE_IMMERSIVE_DARK_MODE` from `AppsUseLightTheme`, re-read on `WM_SETTINGCHANGE` "ImmersiveColorSet" (the live switch is not run) | ✅ measured 2026-10-19 on WSLg, gtk 4.22.4: with `org.gnome.desktop.interface color-scheme` prefer-dark the header bar is RGB 53,53,53, with default or prefer-light 246,245,244 (246,245,244 under prefer-dark before the fix); switching to prefer-dark while `helloWebview` runs turns it dark. GTK reads the portal's `color-scheme` into `gtk-interface-color-scheme`, Ion mirrors it into `gtk-application-prefer-dark-theme` | `windows/core/window.c`, `linux/core/lifecycle.c` |
| Window input records (pointer, key, text, IME, focus, resize, leave) | ✅ measured 2026-10-18 on macOS 26.6 (Retina scale 2, 120 Hz), msc v0.3.4 `3e645dc4c` with `examples/contentInputMacos.ms`, NSEvents posted to the app's own queue (`examples/inputProbeMacos.m`): focus, resize, left button, key (`KeyA` with text `a`, Shift+A with consumed Shift, Enter and Ctrl+C without text, `é`), preedit and commit. On build `212a678c2` the probe also drives right and middle buttons (2, 3), motion, a line and a precise wheel (+dx right, +dy up, the page's `deltaX` sign), leave, and keys through the selected input source (an AppKit-made event retyped, a CGEvent key given its window). Physical trackpad and keyboard the same day: 270 wheel records whose dx sign equals the page's `deltaX` and whose dy sign is opposite to its `deltaY`, buttons 1 and 2, leave, and typed keys with their text, including a Vietnamese input method's Backspace and `á`. Before the fix in `contentHost.m` a horizontal scroll came out as negative dx, and typed text was lost because Text Services reuses the string it hands over | ✅ | ✍️ capture-phase `GtkEventControllerLegacy` + `GtkIMContext`, syntax-checked, not run | `windows/input/input.c` / `macos/core/contentHost.m` / `linux/input/input.c` |
| Pointer forwarding into a webview (`forwardPointer`) | n/a | ✅ | n/a | WebView2 `SendMouseInput`; WKWebView and WebKitGTK take OS input themselves |
| Pointer modifiers (`PointerEvent.mods`, set on button, motion, wheel and leave records) | ✅ measured 2026-10-18 on macOS 26.6 (Retina scale 2, 120 Hz), msc v0.3.4 `3e645dc4c`: a Shift+click reads Shift on the button record (`contentInputMacos`); on build `212a678c2` motion with Ctrl, a precise wheel with Shift and leave with Alt read exactly those modifiers | ✅ measured 2026-10-16: `examples/pointerMods.ms` holds Shift in the thread keyboard state (`SetKeyboardState`, no `SendInput`) and sends `WM_MOUSEMOVE`, `WM_LBUTTONDOWN` and `WM_LBUTTONUP` to the window procedure: 3 of 3 `onPointer` events read Shift; with Shift cleared 0 of 3 do; with the producer line removed the probe FAILs. `currentMods()` is read as the message is processed. Wheel and leave are not driven by the probe | ✍️ `gtk_event_controller_get_current_event_state` through `modsFromState`; compiled and `test/common/inputEvents.ms` passes in WSL, but the modifier state of a real pointer event was not observed: GTK4 cannot synthesize a GdkEvent and no WSLg input was injected | `windows/input/input.c` / `macos/core/contentHost.m` / `linux/input/input.c`; `test/common/inputEvents.ms` pins a button record with Shift and a motion record with Ctrl and Alt through `dispatchInput` |
| Window frame clock (`FrameOnDemand` / `FrameContinuous`) | ✅ measured 2026-10-18 on macOS 26.6 (Retina scale 2, 120 Hz), msc v0.3.4 `3e645dc4c`: a CADisplayLink on the first visible window's content host. `examples/frameStarve.ms` per 2 s: idle 240 frames, `ionWakeLoop` flood 260, `setTimeout(f, 0)` chain 240 (before: 119 / 13 / 109 on the 16 ms poll). `examples/frameStateMacos.ms` per 1 s: about 120 active, restored, shown, inactive with FrameWhenInactive, uncovered; 0 minimized, hidden, another window active, covered by another window (`SDL_WINDOW_OCCLUDED`). `loopWake`'s requested frame came 6 ms after the request | ✅ measured 2026-10-17 with `examples/frameStarve.ms` (continuous policy, 2 s phases, handlers spin 100 us): idle 330 frames; under a `ionWakeLoop` flood the old wait order (wake before tick) gave 44 frames, the tick-first order 363; a self re-arming `setTimeout(f, 0)` kept 330 of 330 on both orders. Re-measured 2026-10-19 (Windows 11, 165 Hz, msc v0.3.4, debug build): handler work per timer run of 0.1 / 2 / 8 / 20 ms keeps 330 / 329 / 83 / 34 frames of a 330 baseline (timer chain alone) and 329 / 328 / 83 / 33 beside an `ionWakeLoop` flood. The 8 and 20 ms loss is not `ionPollEvent`'s due-deadline `return 5` (fewer than 21 hits in 21000 waits): msc runs due timers three times per loop turn (`msRunOnce` steps 1 and 3 and `ion_msc_next_delay_ms` in `ionLoopArm`), so one frame per three handler runs. A wake is served once per turn. `examples/vsyncGuard.c` (2026-10-19, the vsync thread loop on its own window): `DCompositionWaitForCompositorClock` returned 0 on every call, 495 to 500 intervals per 3 s phase at p50 6.06 ms, min 5.74 ms, none under 1 ms, while visible, minimized, restored and covered by a second topmost window; after a 200 ms pause a call took 2 to 22 ms in the quiet run. Display asleep not tested. 2026-10-20 (msc v0.3.4, recompiler `8a9fc02dd`, 165 Hz): the vsync thread waits on `IDXGIOutput::WaitForVBlank` of the monitor of the window that requested a frame last, re-resolves it when that monitor changes or the wait fails, falls back to the compositor clock when no output resolves, and sleeps one refresh period after a failed or sub-millisecond wait. `examples/frameLatency.ms` idle-250 p50 / max over three runs: 3.31 / 6.45, 3.14 / 6.42, 2.99 / 6.49 ms (PASS line: p50 within 3 periods); the old compositor clock gave 6.95 / 84.4 (p90 81.0), 3.37 / 5.97 and 3.16 / 5.95 on the same day, so its 50 to 270 ms first-call stall seen earlier did not reproduce in these quiet runs, and `vsyncGuard --idle` showed plain and vblank first calls both under 6 ms. Idle CPU 0.000% except one run at 15.62 ms in 3 s (both old and new). `frameStarve` with the vblank tick: A 330, B 363, C and D 329 to 330 at 0.1 and 2 ms work, unchanged from the old tick; the 8 and 20 ms rows still fail as before. 2026-10-21 (msc build `b1f63337f`): `ionLoopArm` peeks the next timer with `msNextTimerDelayMs` instead of running due timers a third time, and an already due timer makes the wait poll the tick, the wake and the message queue at timeout 0 instead of returning before them (the peek alone gave 0 frames under a `setTimeout(f, 0)` chain). `frameStarve` C/D: 0.1 ms work 328 / 330 frames with 19631 / 19180 timer runs (before: 10287 / 19386), 2 ms 330 / 330 (313 / 322), 8 ms 124 / 125 (83 / 84), 20 ms 50 / 50 (33 / 33); the 8 and 20 ms rows stay below the half-of-idle bar because msc's `msRunOnce` still runs due timers twice per turn. `frameLatency`, `modalLoop` and `ringProbe` PASS. macOS shares `ion_msc_next_delay_ms` and already polls at timeout 0 when a timer is due; not compiled there. Not run: a sleeping display, an unplugged or mode-changed monitor, two monitors. Windows move/size loop: `ionWndProc` starts a 10 ms timer on WM_ENTERSIZEMOVE and WM_ENTERMENULOOP, and each WM_TIMER serves a pending tick and runs one MS turn (`ionModalTurn`, `msRunOnce(0)` plus every ready record through `ionPollReady`) with a re-entry guard; `examples/modalLoop.ms` per 2 s during SC_MOVE: 127 frames, 127 interval runs, 127 wake handler runs (before: 0 / 0 / 0; outside the loop 331 / 191 / 384), PASS at a quarter of the control rate; the rate is the system timer step (about 15.6 ms), not the display rate. `examples/ringProbe.ms` (2026-10-20) moves the window 500 times inside SC_MOVE: the app gets 501 MOVED events and the later resize, no `ring full` line, also with no spacing between moves (before the pump: 65 delivered, 436 dropped by the 64-entry ring). macOS and Linux have no such loop: `ionPollReady` returns 0 | ✅ measured 2026-10-16 in WSL Ubuntu on WSLg (Wayland), gtk4 4.22.4: `loopWake` gets its one requested frame from the tick callback; a continuous policy is not run | `common/frameClock.c`; Windows compositor clock in `windows/webview/poll.c`; macOS display link in `macos/core/frame.m` |
| `runLoop` runs msc's loop (`setTimeout`, `await` of a `spawn`, actor messages) | ✅ measured 2026-10-18 on macOS 26.6 (Retina scale 2, 120 Hz), msc v0.3.4 `3e645dc4c` (`examples/loopWake.ms`): the `await` of a `spawn` resumed 59 ms after the running line, the 500 ms `setTimeout` fired at 512 ms. Idle `loopWake` between 1.5 s and 4.5 s (`proc_pid_rusage`): 0.0-0.7 ms CPU and 1 wakeup over 3 s, against 24.2 ms and 347 wakeups (116/s) on the earlier 16 ms wait. An idle app still takes a deep link, an AppleScript quit, and SIGINT or SIGTERM under a pty (quit in 46-82 ms, as on the 16 ms wait). Each turn drains one autorelease pool (`poll.m`); measured 2026-10-22, msc v0.3.4 `d64faf905`, `examples/autoreleaseMacos.ms` under an `ionWakeLoop` flood: +314983 malloc blocks in 4 s before (every `NSEvent` autoreleased with no pool), -579 and +2141 on two runs after | ✅ measured 2026-10-15 | ✅ measured 2026-10-16 in WSL Ubuntu on WSLg (Wayland), gtk4 4.22.4: `examples/loopWake.ms` logs the `await` of a `spawn` resuming in `runLoop` and the 500 ms `setTimeout` firing (620 ms after the "running" line: the first poll turn realizes the window; not investigated) | `msRunOnce(0)` each turn; Windows `windows/webview/poll.c` waits on msc's next timer and a watcher on msc's IOCP; macOS `macos/webview/poll.m` waits in Cocoa on msc's next timer, with a watcher on msc's kqueue; Linux polls every 16 ms |
| `ionWakeLoop` from any thread, `onWake` | ✅ measured 2026-10-18 on macOS 26.6 (Retina scale 2, 120 Hz), msc v0.3.4 `3e645dc4c` (`loopWake`): `onWake` 5002 ms after `wakeAfter(5000)`. Wakes coalesce into one posted NSEvent per loop turn; before coalescing, a flood filled SDL's 65535-event queue and `ionWakeLoop` aborted (`frameStarve`) | ✅ measured 2026-10-15 | ✅ measured 2026-10-16 in WSL Ubuntu on WSLg (Wayland), gtk4 4.22.4: `loopWake` logs `onWake` 5000 ms after `wakeAfter` and one frame; idle CPU not sampled | event in the Win32 wait list / an application-defined NSEvent posted to the Cocoa wait / `GCond` signalled into the 16 ms wait |
| Text clipboard (`readClipboardText`, `writeClipboardText`) | ✅ measured 2026-10-18 on macOS 26.6 (Retina scale 2, 120 Hz), msc v0.3.4 `3e645dc4c`: `examples/clipboardOnly.ms` PASS and `loopWake` round-trips `é中文` | ✅ measured 2026-10-15 | ✅ measured 2026-10-16 in WSL Ubuntu on WSLg (Wayland), gtk4 4.22.4: `loopWake` writes and reads back `é中文` (the local read path; a read of another process's clipboard pumps the main context up to 2 s and then prints an error and returns ""; that path is not run) | `CF_UNICODETEXT` / `NSPasteboard` / `GtkClipboard` |
| IME preedit cursor in UTF-16 units | ✅ measured 2026-10-18 on macOS 26.6 (Retina scale 2, 120 Hz), msc v0.3.4 `3e645dc4c` (`contentInputMacos`, NSTextInputClient calls): preedit `日本` caret 1 and `😀x` caret 3 report cursors 1 and 3; the commit `日本語` arrives as text with an empty preedit. Through a real input method on build `212a678c2`: Apple's Vietnamese Simple Telex, selected by the probe and fed `vieejt` and space as keyboard events, gives preedits `i@1 ie@2 iê@2 iệ@2 iệt@3`, then an empty preedit, and the typed text `việt ` | ✍️ written, not driven (needs an IME) | ✍️ ported, syntax-checked, not run | the conversion `ion_utf16_units` is tested (`test/common/utf16.ms`); `GCS_CURSORPOS` and `NSRange` are already UTF-16 |
| Audio file playback (`loadSound`, play, pause, stop, seek, volume, loop, mute, rate, status) | ✅ measured 2026-10-18 on macOS 26.6 (default devices, run from a terminal): `examples/audio.ms` prints `audio example: ok`; the 2 s recording plays back (`durationMs=2000`, position 310 ms after 300 ms, seek to 1200, `finished` once), m4a is refused | ✅ | ✅ measured 2026-10-16 in WSL Ubuntu on WSLg (Wayland), gtk4 4.22.4 through PulseAudio on WSLg: `examples/audio.ms` prints `audio example: ok` (ALSA prints card errors to stderr first); one early run in a loaded machine stopped silently after the recording line and did not reproduce in four later runs | `common/audio.c` on miniaudio `ma_engine`; same C file on all three |
| Audio PCM streams (`openAudioOutput` / `openAudioInput`, ring buffer, underrun counter) | ✅ measured 2026-10-18 on macOS 26.6: `audio.ms` writes 94 x 1024 sine frames at 48 kHz in 1878 ms, `underruns=0` | ✅ | ✅ measured 2026-10-16 in WSL Ubuntu on WSLg (Wayland), gtk4 4.22.4: `audio.ms` sine written, `underruns=0` | `common/audio.c`: `ma_device` + SPSC `ma_pcm_rb`, C-only device callback |
| Audio recording (`startRecording`, pause, resume, stop, status) | ✅ measured 2026-10-18 on macOS 26.6: `audio.ms` records 2 s to a 192044-byte WAV (`durationMs=2000`) holding real input (peak 707 of 32767, 94966 of 96000 samples non-zero) | ✅ | ✅ measured 2026-10-16 in WSL on WSLg: `audio.ms` records 2 s to a 192280-byte WAV (`durationMs=2002`) | `common/audio.c`: capture `ma_device` into `ma_encoder`, WAV 16-bit only |
| Microphone access (`microphoneAccess`, `requestMicrophoneAccess`) | ✅ measured 2026-10-18 on macOS 26.6: `examples/mediaPermission.ms` bundled with `make-app.sh` and launched with `open` reads `undetermined` (`canAskAgain` true), shows the TCC prompt, and reads `granted` (`canAskAgain` false) after Allow. Turned off in Privacy & Security, check and request read `denied` (`canAskAgain` false) with no prompt (measured 2026-10-19); Don't Allow at the prompt itself was not measured. A rebuilt ad-hoc bundle under the same id reads `undetermined` again, and its request answers `granted` with no prompt (measured 2026-10-18 and 2026-10-19). `AVCaptureDevice` check and `requestAccessForMediaType` in `macos/security/microphone.m`; `make-app.sh` writes a fixed `NSMicrophoneUsageDescription` (no manifest field exists), a hardened app also needs the `com.apple.security.device.audio-input` entitlement | ✅ measured 2026-10-16: `examples/mediaPermission.ms` on an unpackaged exe reads `granted` through `DeviceAccessInformation` (AudioCapture, the call Electron makes); no OS prompt exists for desktop apps, so request returns the state and `canAskAgain` is false. Settings flip measured the same day: turning "Microphone access" off gives `denied`, and on again gives `granted` (watched twice against the `ConsentStore` value); the "Let desktop apps access your microphone" toggle was not flipped, so whether `DeviceAccessInformation` follows it is not measured | ✅ measured 2026-10-16 in WSL Ubuntu: `granted`, `canAskAgain: true`; with `/.flatpak-info` present it is the error `running inside Flatpak: the microphone portal is not built` (not run) | `permission.ms` owns the build directives (`platform/*/security/mediaAccess.*`); the native call blocks, so request runs on a `spawn` |
| Camera access (`cameraAccess`, `requestCameraAccess`) | ✅ measured 2026-10-19 on macOS 26.6, msc v0.3.4 `212a678c2`: `examples/mediaPermission.ms` with `--args camera`, bundled with `make-app.sh` (which writes a fixed `NSCameraUsageDescription`) and launched with `open`, reads `undetermined` (`canAskAgain` true), shows the TCC prompt with that description, and reads `granted` (`canAskAgain` false) after Allow. Turned off in Privacy & Security, check and request read `denied` (`canAskAgain` false) with no prompt; Don't Allow at the prompt itself was not measured. `AVMediaTypeVideo` through the microphone's code; a hardened app also needs `com.apple.security.device.camera` | ✍️ `DeviceAccessInformation` for VideoCapture through the microphone's code; cross-compiled from macOS, not run | ✍️ `granted` outside Flatpak, as for the microphone; `clang -fsyntax-only -Wall -Wextra` clean on macOS, not built on Linux | same as the microphone; both return `MediaAccess` |
| OTA `check` / `download` / verify | ✅ measured 2026-10-18 on macOS 26.6: `bash examples/updateMacos.sh` serves a signed manifest on localhost; `check` finds 2.0.0 from 1.0.0 and nothing from 2.0.0, `download` refuses the artifact under another public key (`ed25519 signature verification failed`), `checkWebview` + `applyWebview` swap in the signed web bundle | ✅ | ✅ | pure MS (`src/update.ms`) |
| OTA `apply` (install + relaunch) | ✅ measured 2026-10-18 on macOS 26.6 with `examples/updateMacos.sh`: 1.0.0 downloads and mounts the 2.0.0 `.dmg`, copies the app beside itself and swaps it in with `renamex_np(RENAME_SWAP)`, and 2.0.0 is relaunched; on an HFS+ volume (where the swap is `ENOTSUP`) two renames do it; with `LOCKED=1` (read-only directory) one admin prompt installs it and the bundle keeps its owner, and Cancel there returns `user cancelled the admin authorization` with 1.0.0 in place and no `.dmg` mounted. No admin prompt when the directory is writable | ⛔ stub | ✅ measured 2026-10-18 in WSL on an AppImage: `examples/updateLinux.ms` version 1 copies version 2 beside itself, `rename(2)`s it over `$APPIMAGE` and relaunches as version 2; in a read-only directory it prints `[ion] update: cannot create …: Permission denied` and version 1 stays. `apply` from a manifest server (download, verify, install) not run end to end | `update/install.{m,c}`, linked from `update.ms` |

Window text input, measured 2026-10-15 on Windows 11: `examples/textFilter.ms` sends `WM_CHAR` and `WM_SYSCHAR` straight to the window procedure (so `TranslateMessage` is not exercised) and asserts `onText`. Units below 0x20 and DEL produce no text and no key record `text`, `WM_SYSCHAR` (Alt accelerators) produces none, and printable units, surrogate pairs and Ctrl+Alt (AltGr) text still arrive; this matches macOS `isTypedText` and winit `keyboard.rs:232-250`.

Multi-window, measured 2026-10-16 on Windows 11 (msc v0.3.4, build `fd03df3e`): `examples/multiWindow.ms` opens windows `one` and `two`, each with a D2D panel and a webview, and drives them by posting messages to each HWND. Pointer and key records carry their own window id; each webview's `ready` is answered by `emit` to the sending webview and acked from that webview; a click forwarded into each webview reaches that page; `PrintWindow` reads each panel's color. After `WM_CLOSE` to `one`: `close-requested` and `destroyed` for `one`, `windowCount` 1, its webview released, and `two` still takes a click, a frame, an IPC round trip and draws a panel added after the close. `WM_CLOSE` to `two` ends the loop; exit 0, 15 PASS. All windows share one DirectComposition device (each has its own target and root), so `windowDevice` is the same pointer for every window and one commit covers all of them.

Window controls and events, measured 2026-10-15 on a Windows 11 host (one 3440x1440 monitor at 96 dpi): `msc build examples/windowControls.ms`, then run; it reads each control back through Win32 (`GetClientRect`, `GetWindowRect`, style and exstyle bits, `IsWindowVisible`, `IsIconic`, `IsZoomed`, `GetWindowTextW`) and exits 1 on a FAIL. A window another app has pulled the foreground from skips the `blurred` check on minimize.

Loop, wake and clipboard, measured 2026-10-15 on msc v0.3.3 (build `9cf5708c`), Windows 11:
`examples/loopWake.ms` logs the 500 ms `setTimeout` firing 500 ms after start, an `await` of a
`spawn` resuming inside `runLoop`, the clipboard round trip of `é中文`, and a raw `CreateThread`
calling `ionWakeLoop` after 5 s: `onWake` runs and one frame is drawn. Process CPU time over 3 s
idle, before and after the wake: 0 ms and 0 ms (two runs; the clock ticks at 15.6 ms). The macOS
code is measured on macOS 26.6 (2026-10-18): see the measured rows. The Linux code compiles with
`gcc -fsyntax-only -Wall -Wextra` against gtk4 4.22.4, webkitgtk-6.0 2.52.6, ayatana-appindicator-glib 2.0.1, libnotify 0.8.8 and libsecret 0.21.7 in WSL Ubuntu (2026-10-16) and ran on WSLg 2026-10-16 with msc v0.3.3 (0f8278bc): see the measured rows. The preedit cursor was not
driven by a real IME.

Native LOC: macOS 1715 · Windows 2119 · Linux 2206 (GTK4 port, 2026-10-16) · shared C 1392.
MetaScript LOC: 2016 across 20 modules.

Audio, measured 2026-10-15 on a Windows 11 host with `msc` v0.3.3, default devices: `examples/audio.ms` recorded
2 s mono 48 kHz (`out/rec.wav`, 192044 bytes, 96000 frames, nonzero samples, read back with Python `wave`), loaded it
at `durationMs=2000`, seek to 1200 ms landed at 1200, `finished` flipped true once at position 2000, a 440 Hz sine
written from MetaScript as 94 x 1024 frames at 48 kHz gave `underruns=0`, and `x.m4a` returned
`unsupported audio format .m4a`. A probe decoded wav, flac, mp3 and ogg vorbis (ffmpeg-made, 2 s each; duration 2000 ms,
`finished` once). Format set: playback wav, flac, mp3, ogg vorbis (miniaudio decoders + vendored `stb_vorbis`);
recording WAV only; anything else is a named error and m4a/aac has no decoder. `rate` is pitch (speed and pitch move
together). macOS (2026-10-18) and Linux (2026-10-16, WSLg) run the same `audio.c`, with
`-framework CoreFoundation/CoreAudio/AudioToolbox` and `-ldl -lpthread -lm` in `src/audio.ms`; results in the rows above. Limits: status is polled (`setInterval`
at the app's progress interval, the expo-av model); `audio.c` does not call `ionWakeLoop`, so audio
links without the window host; the recording callback writes the file on the device
thread, so a slow disk drops input; no device enumeration, effects or MetaScript audio callback.

Project generation, measured 2026-09-22: macOS and iOS arm64 development
applications build through Xcode. iOS simulator Debug/Release launch, ad-hoc
signing and unsigned device builds are verified. Android arm64 (measured
2026-09-23): a Gradle project builds Debug and signed Release APK/AAB and runs
the JNI lifecycle fixture on the Android 36 emulator and a physical Seeker phone. A package's Java
reaches that project as an Android library module it declares with `androidLibrary`
(`src/android.ms`; measured 2026-09-25 on the emulator). Neither ports Ion's
runtime APIs or integrates Neon. See
[PROJECT-GENERATOR.md](docs/PROJECT-GENERATOR.md#verification) for the measured
tree, command and remaining boundaries.

Windows desktop application, measured 2026-10-14 on msc v0.3.3 with Build
Tools 2022: a `Target.windowsApp` manifest generates a Visual Studio solution
whose MSBuild Debug and Release builds put the executable, `WebView2Loader.dll`
and the declared assets in `resources/`; `examples/helloWebviewProject.ms`
launched from another directory logs `auto-probe: ipc alive`. With NSIS 3.13,
`ion app <exe> IonHello dev.ion.IonHello --target windows --asset examples/hello.html`
builds `out/IonHello-setup.exe` (463 KB, unsigned). Not measured: running that
installer (per-machine, needs elevation), Visual Studio IDE debugging, an icon
resource.

Linux application, measured 2026-10-18 in WSL Ubuntu 26.04 on WSLg with
appimagetool 1.9.1: `ion app out/debug/helloWebview IonHello dev.ion.IonHello
--target linux --asset examples/hello.html` builds `out/IonHello-x86_64.AppImage`
(2.3 MB); started from `/tmp` it logs `auto-probe: ipc alive`, `MS command
addNumbers(100, 23)` and `[ion] IPC rejected: invalid invoke_key`. GTK4 and
WebKitGTK 6.0 come from the user's system (decided 2026-10-18); the binary's
highest glibc symbol is `GLIBC_2.36`. Not measured: a distro older than the
build host (Ubuntu 24.04 ships GTK 4.14, and a GTK call newer than that fails
at load), AppStream metainfo, desktop integration (menu entry, URL scheme).

Windows Android build-host boundary, measured 2026-09-30: unified generation
and the generated NDK tool selection run on Windows. APK construction is
compiler-blocked by the Windows batch-tool invocation recorded in workspace
card `.inbox/compiler/2026-09-20-emcc-spawn-windows.md`; no Android runtime host,
native-load, Release-JNI or lifecycle claim follows from that generation.
Commands and limits are in `docs/PROJECT-GENERATOR.md`, "Windows build-host
boundary". No generated-project workaround is approved.

## What the old docs got wrong

These are already corrected in `README.md` / `CLAUDE.md` as of this pass, but
recorded here so nobody re-introduces them:

- ⚠️ **"Linux not started"** — Linux is fully wired (1508 LOC, 20 files),
  including keychain via libsecret and the `@comptime pkg-config` flag
  resolution that used to be parked.
- ⚠️ **"Windows: only NSIS packaging pending"** — `scripts/make-app-windows.nsi`
  + `scripts/utils.nsh` exist.
- ⚠️ **"Not a multi-window manager — v0 is single-window"** — `windowManager.ms`
  (227 LOC) exports 25 symbols; `common/windowRegistry.c` backs it on all three
  platforms.
- ⚠️ **"GPU surface deferred indefinitely"** — `renderSurface.ms` (78 LOC) +
  `macos/core/renderSurface.m` shipped, with a 203-line design doc.
- ⚠️ **"OTA not implemented"** — client is real; only the *install* step is
  macOS-only.
- ⚠️ **`command-builder/`** — referenced by README, **does not exist**. That CLI
  library now lives at `src/cli/index.ms` (347 LOC) with tests in `src/cli/test/`;
  `cli/main.ms` is the `ion` CLI built on it.
- ⚠️ **`bin/ion`** — referenced by README as the shipped CLI binary; **no `bin/`
  directory on disk**. Every `./bin/ion …` line in the README is currently
  unrunnable.
- ⚠️ **`scripts/build-release.sh`** — referenced by CLAUDE.md; not present.

## Open work

### P0 — Publish readiness (blocks making this a repo)

Done:

1. ~~**`git init`**~~ — done. `origin` → `git@github.com:metascriptlang/ion.git`.
2. ~~**`.gitignore`**~~ — covers `out/`, `*.o`, `web/dist/`, packaged artifacts.
   `vendor/webview2/` is deliberately kept: version pinned at 1.0.2849.39 and the
   Windows build depends on those exact headers.
3. ~~**Strip personal paths**~~ — no `/Users/<user>` references remain.
4. ~~**Fix `build.ms`**~~ — `entry` → `./src/index.ms`; `files` widened to include
   `.c/.h/.m/.cpp/.hpp` + `vendor/webview2` + `scripts` + `assets`, without which
   a published package cannot build. Version still `0.0.1`.
5. ~~**De-brand the source**~~ — no file names the original consumer app. The
   one real defect was `macos/update/install.m`, which hardcoded the consumer's
   name into the osascript admin prompt shown to **every** ion app's users; it
   now derives the app name and destination from `destAppPath`.

Remaining:

6. **Answer "how does a stranger build this?"** — the build depends on
   `~/metascript/recompiler` being present and containing the fixes listed under
   *Cross-references* below. Without a public/pinned recompiler, a clone is not
   buildable. This is the real gate on going public, not code quality.
7. **`vendor/webview2/runtime/x64/WebView2Loader.dll`** — a prebuilt Microsoft
   binary committed into an MIT repo. Confirm the SDK licence permits
   redistribution, or fetch it at build time instead.

### P1 — Doc truth

- `docs/MULTI-WINDOW.md` drifts from the shipped API: it imports
  `getAllWindows` and `setContentProtected`, but `src/index.ms` exports
  `windowCount` and `setWindowContentProtected`. Reconcile.
- `web/` (607 LOC TS package with its own `package.json` / `tsconfig.json` /
  tests) is undocumented everywhere. Decide whether it ships and describe it.

### P2 — Feature gaps

- **OTA install on Windows** — design already noted in
  `platform/windows/update/install.c`: NSIS `.exe` spawned elevated via
  `ShellExecuteEx` + `runas`, or `MOVEFILE_REPLACE_EXISTING` for in-place.
- **Menu bar on Windows / Linux** — not planned: decided 2026-10-16 that the
  app draws its menu in its own content, as VS Code and Discord do; Ion keeps
  only the macOS app menu, which lives outside the window.
- **Window content on Linux** — the input records are syntax-checked, not run
  (matrix). macOS was built and measured on 2026-10-18 (matrix rows).
- **Idle loop on Linux** — `ionPollEvent` waits at most 16 ms per turn, so an
  idle app still turns its loop about 60 times a second. Windows and macOS
  block until a timer, a wake or msc's IOCP / kqueue is due (macOS measured
  2026-10-18: 1 wakeup in 3 s idle, against 116/s at 16 ms); the Linux
  counterpart would watch msc's epoll fd from the GLib main context.
- **Frame clock on Windows 10** — not written: `windows/webview/poll.c` has one
  tick source, `DCompositionWaitForCompositorClock`, and without it prints
  `[ion] frame clock: ... not found` and sends no frame. That the entry point is
  missing on Windows 10 is taken from memory, not checked against its docs or on
  a Windows 10 box. `IDXGIOutput::WaitForVBlank` is the candidate second source.
- **Surface fully covered by other windows** — not written: a continuous surface
  keeps ticking while another window hides it. Windows sends no event for that;
  it needs a geometry tracker over every top-level window. A cloaked window does
  stop its frames, measured with an app cloak (`DWMWA_CLOAK`); a shell cloak
  (switching virtual desktop) goes through the same hook but was not exercised.
  macOS stops a covered window through its occlusion state (measured 2026-10-18,
  `frameStateMacos`).
- **Windows composition hosting** — since WebView2 moved to a
  `CompositionController` (2026-09-23) the host forwards what windowed hosting
  gave for free. Measured 2026-09-23 on WebView2 Runtime 153.0.4234.48: file
  drag and drop from Explorer reaches the page (`webview/host.cpp` drop target →
  `ICoreWebView2CompositionController3`); UI Automation reaches the page's
  Document/Text/Edit under the Ion window, by hosting a UIA element on the
  browser process's top-level `Chrome_WidgetWin_1` popup (an undocumented
  Chromium window, found by class, browser PID and position — recheck on a
  runtime update). Not tried with Narrator/NVDA/JAWS, nor with more than one
  webview. Touch in the webview frame reaches the page as `pointerType`
  "touch" at frame coordinates (`WM_POINTER*` → `SendPointerInput`, measured with
  `InjectTouchInput`, no touch hardware here); outside the frame Windows
  promotes it to mouse input for the surface. Pen measured the same way
  (`InjectSyntheticPointerInput`): the page sees `pointerType` "pen" with its pressure.
- **Touch and pen into a webview on Windows** — reach the page as promoted
  mouse events through the app's forwarding, not as pointer input with
  pressure and contact data (`docs/WINDOW-CONTENT.md`).
- **Toast WinRT** — current Windows notification is a balloon tip (renders via
  the Toast/Action Center pipeline on Win10/11 anyway). Proper
  `ToastNotificationManager` needs an AUMID from a Start Menu shortcut.
- **Windows native build, measured 2026-09-23** (`msc` v0.2.55, build
  `dcfa743b`, Windows 11 host): `msc check src/index.ms` clean, every file
  under `test/` and `test/common/` green, `helloWebview`, `renderSurfaceSmoke`
  and `surfaceD3D11` build and link. The `ionInput*` accessors now live once in
  `common/inputEvents.c`, which also removes the Linux gap of the same name
  (not built on Linux). `surfaceD3D11` measured: D3D11 clear under a
  transparent webview panel, key/text/focus/resize/pointer events printed,
  typing inside the panel reaches the webview and not the surface, IPC round
  trip (`auto-probe: ipc alive`, `addNumbers(100, 23)`) through the
  composition controller. By hand the same day: a DPI change 96 → 144 → 96
  gives one `resize` each (1328x844 at scale 1.5, back to 884x561); UniKey
  Telex types "tiếng việt" into the webview, and its Backspace + `VK_PACKET`
  output reaches the surface as a Backspace key then `text` (replayed with
  `KEYEVENTF_UNICODE`, a surrogate pair arrives whole). Not measured: an
  IMM32/TSF IME composition (`preedit` events) — no Microsoft IME is
  installed on this box.

Windows behaviour that is not a bug: a 1–2 s white flash on the first launch of
a session (WebView2 process spawn + COM init; a splash screen is the answer),
and the GUI subsystem detaching `stdout`/`stderr` from the launching terminal
(`app.exe > log.txt 2>&1` while debugging).

Window class background (2026-10-20): a null class brush with `WM_ERASEBKGND` returning 1 changed
nothing, so the class keeps `COLOR_WINDOW+1`. `examples/nativeContent.ms` shows 808 of 1760 sampled
pixels at (255,255,255) with either class: that white is the DWM redirection surface, not the
brush. `WS_EX_NOREDIRECTIONBITMAP` removed it (`helloWebview` and `nativeContent` still painted) but
made every pixel no layer covers transparent, so Ion leaves it out; an app that needs an opaque
background paints one. Resize strips are not measured.

### P3 — Test coverage

9 test files total, all unit-level and all on pure logic:
`test/{jsescape,hotkeyResult,keycodes,mods}.ms`,
`test/common/{invokekey,queue,navpolicy}.ms`,
`src/cli/test/{dispatch,smoke}.ms`.

Nothing exercises the native layer. Every window / webview / IPC / chrome path
is covered only by the manual smoke test in `CLAUDE.md`. Given three platforms
now share `common/` C code, a headless harness for `windowRegistry`,
`protoReg`, and `mime` would pay for itself quickly.

## Cross-references — MS recompiler changes this repo depends on

Build reproducibility requires these in `~/metascript/recompiler/`:

1. **`runtime/` POSIX type fixes** (4 files): `<sys/types.h>` added to
   `fs/posix.c`, `process.h`, `net/socket.h`, `io/engineReadiness.c`. macOS libc
   included them transitively; Linux glibc is strict. Fixes `mode_t`, `pid_t`,
   `ssize_t`.
2. **`osTarget` → `targetOs` always-set refactor** (9 files, ~65 callsites).
   `CliOptions.osTarget`'s `""` ambiguously meant both "native build" and "no
   explicit cross-compile". Now `targetOs: string` always set, defaulting to
   host `platform`; cross-compile is `targetOs !== platform`.
3. **`codegen/c/expressions.ms` `variantStructCName`** — unified variant struct
   C-name lookup to a single typeCache source of truth. Previously two codegen
   passes resolved variant identity by two different keys; the fallback emitted
   a raw interface name unknown to consumer `.c` files, surfacing as
   `error: 'NativeBuild' undeclared` for cross-file discriminated unions.

## Parked

- **Raiser VM stdlib access** — the `@comptime` VM has a hand-maintained host
  table (`src/compiler/meta/hostTable.ms`, ~20 entries) instead of reaching MS
  `std/*` directly. The `pkg-config` use case that motivated it is now unblocked
  (Linux flags resolve correctly), so this is no longer on ion's critical path.
  The auto-scanner sketched at `hostTable.ms:25-36` would retire the bug class
  permanently. Sơn-driven, dedicated recompiler session.
- **Toast WinRT** — see P2.
