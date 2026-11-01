// Ion Linux — open a URL via xdg-open and wait for its exit status, as the
// `open` crate's `that` (Tauri's shell open) does: xdg-open hands the URL to
// the handler and exits, 0 when one took it.

#include <stdlib.h>
#include <unistd.h>
#include <sys/wait.h>

int ionOpenExternal(const char *url) {
    if (url == NULL || url[0] == '\0') return 0;
    pid_t pid = fork();
    if (pid == 0) {
        execlp("xdg-open", "xdg-open", url, (char *)NULL);
        _exit(127);
    }
    if (pid < 0) return 0;
    int status;
    if (waitpid(pid, &status, 0) != pid) return 0;
    return WIFEXITED(status) && WEXITSTATUS(status) == 0 ? 1 : 0;
}
