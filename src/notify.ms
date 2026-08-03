// OS notifications via UNUserNotificationCenter.
//
// The first notify() call requests permission once; subsequent calls reuse
// the granted state. If the user denies or hasn't responded, calls are
// no-ops until permission is granted in System Settings.
//
// Click on a notification → IPC message "notification.click" delivered to
// listen() handlers with payload = the id you passed at notify time.

import { ionNotify } from "./platform/bridge.h";

export function notify(title: string, body: string, id: string): void {
	ionNotify(title, body, id);
}
