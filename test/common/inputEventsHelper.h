#ifndef ION_TEST_INPUT_EVENTS_HELPER_H
#define ION_TEST_INPUT_EVENTS_HELPER_H

int ionTestPushPointer(int type, int window, double x, double y, double p1, double p2, int mods);
int ionTestPushWheel(int window, double dx, double dy, int unit);
int ionTestPushKey(int window, int action, int vk, const char *text, const char *chordText, const char *allModsText);
int ionTestPushImeKey(int window, int action);

#endif
