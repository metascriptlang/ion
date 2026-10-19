// The macOS menu bar. setAppMenu replaces Ion's default bar (App, File, Edit, View, Window),
// now or when the first window opens, and may be called again to replace it. Clicking a
// MenuItem.action, or pressing its key, sends "menu.click" with the item's id to listen() handlers.
//
//   setAppMenu([
//     { title: "", items: [MenuItem.standard(MenuRole.Hide), MenuItem.standard(MenuRole.Quit)] },
//     { title: "File", items: [MenuItem.action("close_window", "Close Window", "w", ModCmd)] },
//   ]);

// Windows and Linux have no native menu bar: the app draws its menu in its content (TODO.md).
// macOS builds menu.m with the window host in ipc.ms, which installs the default bar.
when (windows) {
	@compile("./platform/common/noMenu.c");
}

when (linux) {
	@compile("./platform/common/noMenu.c");
}

import {
	ionMenuBegin, ionMenuAddSubmenu, ionMenuAddItem, ionMenuAddRole, ionMenuAddSeparator, ionMenuCommit,
} from "./platform/bridge.h";

// Mirror ION_MENU_ROLE_* in bridge.h.
export enum MenuRole {
	About,
	Hide,
	HideOthers,
	ShowAll,
	Quit,
	CloseWindow,
	Minimize,
	Zoom,
	Fullscreen,
	Undo,
	Redo,
	Cut,
	Copy,
	Paste,
	SelectAll,
	Reload,
}

export enum MenuItemKind {
	Action,
	Standard,
	Separator,
}

export struct MenuItem {
	kind: MenuItemKind;
	id: string;
	title: string;
	key: string;
	modifiers: int32;
	role: MenuRole;
}

export struct Submenu {
	title: string;
	items: MenuItem[];
}

// key: "" for none, one character ("w", ","), or "F1".."F12", "Space", "Return"/"Enter", "Tab",
// "Escape"/"Esc", "Delete"/"Backspace", "Up", "Down", "Left", "Right". modifiers: ModCmd | ModShift | ….
export function action(this typeof MenuItem, id: string, title: string, key: string, modifiers: int32): MenuItem {
	return { kind: MenuItemKind.Action, id: id, title: title, key: key, modifiers: modifiers, role: MenuRole.About };
}

// An item AppKit performs with its standard title and key, as Tauri's PredefinedMenuItem.
export function standard(this typeof MenuItem, role: MenuRole): MenuItem {
	return { kind: MenuItemKind.Standard, id: "", title: "", key: "", modifiers: 0 as int32, role: role };
}

export function separator(this typeof MenuItem): MenuItem {
	return { kind: MenuItemKind.Separator, id: "", title: "", key: "", modifiers: 0 as int32, role: MenuRole.About };
}

const ION_MENU_UNSUPPORTED: int32 = -1 as int32;
const ION_MENU_UNKNOWN_KEY: int32 = -2 as int32;

function added(item: MenuItem): int32 {
	return match (item.kind) {
		MenuItemKind.Action => ionMenuAddItem(item.id, item.title, item.key, item.modifiers),
		MenuItemKind.Standard => ionMenuAddRole(item.role as int32),
		MenuItemKind.Separator => ionMenuAddSeparator(),
	};
}

function refused(item: MenuItem, menu: Submenu, code: int32): string {
	const what = code === ION_MENU_UNKNOWN_KEY ? `unknown key '${item.key}'` : `unknown role ${item.role.toString()}`;
	return `setAppMenu: ${what} in '${item.title}' of menu '${menu.title}'`;
}

// The current bar stays when this returns an error.
export function setAppMenu(menus: Submenu[]): Result<void, string> {
	if (ionMenuBegin() === ION_MENU_UNSUPPORTED) {
		return Result.err("setAppMenu: no native menu bar on this platform; draw the menu in the window's content");
	}
	for (const menu of menus) {
		ionMenuAddSubmenu(menu.title);
		for (const item of menu.items) {
			const code = added(item);
			if (code < 0) { return Result.err(refused(item, menu, code)); }
		}
	}
	ionMenuCommit();
	return Result.ok(null);
}
