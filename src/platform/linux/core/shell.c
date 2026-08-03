// Ion Linux — open a URL via xdg-open. Double-fork so the grandchild is
// reparented to init and reaped there, leaving no zombie in our process.

#include <stdlib.h>
#include <unistd.h>
#include <sys/wait.h>

void ionOpenExternal(const char *url) {
    if (url == NULL || url[0] == '\0') return;
    pid_t pid = fork();
    if (pid == 0) {
        if (fork() == 0) {
            execlp("xdg-open", "xdg-open", url, (char *)NULL);
            _exit(127);
        }
        _exit(0);
    }
    if (pid > 0) {
        int status;
        waitpid(pid, &status, 0);
    }
}
