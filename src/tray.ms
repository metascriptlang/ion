// Menu-bar (tray) status item. Single tray per app.
//
// Click → IPC message "tray.click" delivered to listen() handlers, plus
// the main window is brought forward.

import {
	ionInstallTray, ionInstallTrayImage, ionUninstallTray,
} from "./platform/bridge.h";

// Install with a text label. Pass a short string (1-3 chars or an emoji);
// macOS sizes it to fit the menu bar.
export function installTray(title: string): void {
	ionInstallTray(title);
}

// Install with a template PNG icon. The image is rendered as a template
// (auto-adapts to dark/light menu bar) and sized to 18×18.
//
// Path resolution: tries the literal path first, then falls back to the
// .app bundle's Contents/Resources/ via the basename. So callers can pass
// "tray-icon.png" both in dev (relative to cwd) and after bundling.
export function installTrayImage(pngPath: string): void {
	ionInstallTrayImage(pngPath);
}

export function uninstallTray(): void {
	ionUninstallTray();
}
