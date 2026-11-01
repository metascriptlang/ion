// Ion Linux — the app's identifier: the executable's file name, from /proc/self/exe.

#include <limits.h>
#include <string.h>
#include <unistd.h>

#include "../../bridge.h"

msString ionAppIdentifier(void) {
    char path[PATH_MAX];
    ssize_t n = readlink("/proc/self/exe", path, sizeof(path) - 1);
    if (n <= 0) return MS_EMPTY_STRING;
    path[n] = '\0';
    const char *name = strrchr(path, '/');
    return msStringFromCStr(name ? name + 1 : path);
}
