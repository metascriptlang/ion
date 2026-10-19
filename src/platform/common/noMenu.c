// Ion Windows and Linux - no native menu bar: the app draws its menu in its content (TODO.md).

#include "../bridge.h"

int ionMenuBegin(void) { return ION_MENU_UNSUPPORTED; }
int ionMenuAddSubmenu(const char *title) { (void)title; return ION_MENU_UNSUPPORTED; }
int ionMenuAddItem(const char *itemId, const char *title, const char *key, int modifiers) {
	(void)itemId; (void)title; (void)key; (void)modifiers;
	return ION_MENU_UNSUPPORTED;
}
int ionMenuAddRole(int role) { (void)role; return ION_MENU_UNSUPPORTED; }
int ionMenuAddSeparator(void) { return ION_MENU_UNSUPPORTED; }
int ionMenuCommit(void) { return ION_MENU_UNSUPPORTED; }
