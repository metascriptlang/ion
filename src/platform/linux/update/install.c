// Linux OTA install: the app ships as an AppImage, so an update is one file
// copied beside the running AppImage and renamed over it. rename(2) is atomic
// on one filesystem; the running process keeps the old inode until it exits.

#include <errno.h>
#include <fcntl.h>
#include <spawn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include "../../bridge.h"
#include "runtime/core/string.h"

extern char **environ;

#define ION_UPDATE_NOT_IMPL (-99)

msString ionUpdateMountDmg(const char *dmgPath) {
	(void)dmgPath;
	return MS_EMPTY_STRING;
}

msString ionUpdateFindAppInVolume(const char *mountPoint) {
	(void)mountPoint;
	return MS_EMPTY_STRING;
}

int ionUpdateUnmountDmg(const char *mountPoint) {
	(void)mountPoint;
	return ION_UPDATE_NOT_IMPL;
}

// The download sits in a temp dir that may be another filesystem, where
// rename(2) fails with EXDEV, so the copy lands in the destination's own dir.
int ionUpdateReplaceApp(const char *srcAppPath, const char *destAppPath) {
	if (!srcAppPath || !destAppPath || !*destAppPath) return -1;
	char tmp[4096];
	if (snprintf(tmp, sizeof(tmp), "%s.update", destAppPath) >= (int)sizeof(tmp)) return -1;

	int in = open(srcAppPath, O_RDONLY | O_CLOEXEC);
	if (in < 0) {
		fprintf(stderr, "[ion] update: cannot open %s: %s\n", srcAppPath, strerror(errno));
		return -2;
	}
	int out = open(tmp, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0755);
	if (out < 0) {
		fprintf(stderr, "[ion] update: cannot create %s: %s\n", tmp, strerror(errno));
		close(in);
		return -2;
	}
	char buf[65536];
	ssize_t n;
	int failed = 0;
	while ((n = read(in, buf, sizeof(buf))) > 0) {
		for (ssize_t off = 0; off < n;) {
			ssize_t w = write(out, buf + off, (size_t)(n - off));
			if (w < 0) { if (errno == EINTR) continue; failed = 1; break; }
			off += w;
		}
		if (failed) break;
	}
	if (n < 0) failed = 1;
	if (!failed && (fchmod(out, 0755) != 0 || fsync(out) != 0)) failed = 1;
	int saved = errno;
	close(in);
	if (close(out) != 0 && !failed) { failed = 1; saved = errno; }
	if (failed) {
		fprintf(stderr, "[ion] update: cannot write %s: %s\n", tmp, strerror(saved));
		unlink(tmp);
		return -2;
	}
	if (rename(tmp, destAppPath) != 0) {
		fprintf(stderr, "[ion] update: cannot replace %s: %s\n", destAppPath, strerror(errno));
		unlink(tmp);
		return -4;
	}
	return 0;
}

// The relaunched app would find this process still owning the single-instance
// bus name and hand off to it, so the helper waits for this pid to exit first.
int ionUpdateRelaunchAndExit(const char *destAppPath) {
	if (!destAppPath || !*destAppPath) return -1;
	char script[128];
	snprintf(script, sizeof(script),
		"while kill -0 %d 2>/dev/null; do sleep 0.1; done; exec \"$0\"", (int)getpid());
	char *const argv[] = { "/bin/sh", "-c", script, (char *)destAppPath, NULL };
	pid_t child = 0;
	if (posix_spawn(&child, "/bin/sh", NULL, NULL, argv, environ) != 0) return -5;
	_exit(0);
}
