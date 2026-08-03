// Open a URL in the user's default browser / handler app. The Ion
// equivalent of Tauri's @tauri-apps/plugin-shell open(). Used by the OAuth
// loopback flow to launch the provider's consent page.

import { ionOpenExternal } from "./platform/bridge.h";

export function openExternal(url: string): void {
	ionOpenExternal(url);
}
