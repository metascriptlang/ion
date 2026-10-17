// Ion macOS — OTA install bridge.
//
// Four primitives, stateless: mount the .dmg, find the .app inside, replace
// the installed .app (an admin prompt only when its directory is not writable), detach the
// image, then spawn a detached helper that waits for our pid to die before
// opening the new .app. Caller (std/ion update.ms) does the verify, scoring,
// and progress UX; this file is pure plumbing.
//
// The privileged path uses AppleScript "do shell script with administrator privileges". The non-deprecated alternative, AuthorizationServices
// + SMAppService, requires shipping a privileged helper tool with a one-time
// SMJobBless install — overkill for v0. AppleScript admin prompts use the
// system auth dialog (Touch ID supported) and need no helper. Sparkle's
// fallback path + Tauri-updater both ship this exact pattern.

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <spawn.h>
#include <errno.h>
#include <sys/time.h>
#include "../../bridge.h"
#include "runtime/core/string.h"

extern char **environ;

// Run a child process to completion, return its exit code. stdout/stderr
// are discarded; we don't need hdiutil's plist output because we pass an
// explicit -mountpoint flag.
static int runTaskSync(NSString *launchPath, NSArray<NSString *> *args) {
	NSTask *task = [[NSTask alloc] init];
	task.launchPath = launchPath;
	task.arguments = args;
	task.standardOutput = [NSPipe pipe];
	task.standardError = [NSPipe pipe];
	@try { [task launch]; }
	@catch (NSException *e) { return -1; }
	[task waitUntilExit];
	return (int)task.terminationStatus;
}

static msString msStringFromNSString(NSString *s) {
	if (!s) return MS_EMPTY_STRING;
	const char *utf = s.UTF8String;
	return msStringNew(utf, (int64_t)strlen(utf));
}

// sh-quote a path for safe embedding inside `'...'` in /bin/sh. Single quote
// is the only character that can break out of a single-quoted shell string,
// and the standard escape is to close the quote, emit an escaped quote,
// and reopen: `O'Brien` → `'O'\''Brien'`. Apple permits `'` in app names so
// this is real, not theoretical — combined with the AppleScript outer
// escape below it makes the install path injection-safe even if a future
// release of ion-ota allows partner-signed bundles whose names we don't
// control.
static NSString *shQuoteCString(const char *cstr) {
	if (!cstr) return @"''";
	NSString *raw = @(cstr);
	NSString *escaped = [raw stringByReplacingOccurrencesOfString:@"'"
	                                                   withString:@"'\\''"];
	return [NSString stringWithFormat:@"'%@'", escaped];
}

// Escape a fully-formed shell command for embedding inside an AppleScript
// double-quoted string ("..."). AppleScript treats `\` and `"` as special;
// other characters (including `'` and `$`) pass through verbatim.
static NSString *appleScriptEscape(NSString *shCommand) {
	NSString *step1 = [shCommand stringByReplacingOccurrencesOfString:@"\\"
	                                                       withString:@"\\\\"];
	return [step1 stringByReplacingOccurrencesOfString:@"\""
	                                        withString:@"\\\""];
}

msString ionUpdateMountDmg(const char *dmgPath) {
	if (!dmgPath) return MS_EMPTY_STRING;

	NSString *dmg = @(dmgPath);
	NSString *mountPoint = [NSString stringWithFormat:@"/tmp/ion-mount-%@",
	                         [[NSUUID UUID] UUIDString]];

	// `hdiutil attach -nobrowse -noverify -noautoopen -mountpoint <path>`
	// Mounts silently at a known path, suppresses Finder window pop-up.
	int rc = runTaskSync(@"/usr/bin/hdiutil",
		@[@"attach", @"-nobrowse", @"-noverify", @"-noautoopen",
		  @"-mountpoint", mountPoint, dmg]);
	if (rc != 0) return MS_EMPTY_STRING;

	return msStringFromNSString(mountPoint);
}

msString ionUpdateFindAppInVolume(const char *mountPoint) {
	if (!mountPoint) return MS_EMPTY_STRING;

	NSString *mp = @(mountPoint);
	NSError *err = nil;
	NSArray *names = [[NSFileManager defaultManager]
		contentsOfDirectoryAtPath:mp error:&err];
	if (!names) return MS_EMPTY_STRING;

	for (NSString *name in names) {
		if ([name.pathExtension isEqualToString:@"app"]) {
			NSString *appPath = [mp stringByAppendingPathComponent:name];
			return msStringFromNSString(appPath);
		}
	}
	return MS_EMPTY_STRING;
}

// The new bundle is copied beside the old one, on its volume, and exchanged with it by
// renamex_np(RENAME_SWAP), so the install path never stops holding a complete app.
// HFS+ cannot swap; there the old bundle moves aside, the new one moves in, and the old
// one is moved back if that second rename fails. The admin prompt appears only when the
// destination's directory is not writable, as for a standard user's /Applications.
static int moveIntoPlace(NSString *staged, NSString *dest, NSString *backup) {
	if (renamex_np(staged.fileSystemRepresentation, dest.fileSystemRepresentation, RENAME_SWAP) == 0) {
		[[NSFileManager defaultManager] removeItemAtPath:staged error:nil];
		return 0;
	}
	if (errno == ENOENT && access(dest.fileSystemRepresentation, F_OK) != 0) {
		return rename(staged.fileSystemRepresentation, dest.fileSystemRepresentation) == 0 ? 0 : -1;
	}
	if (rename(dest.fileSystemRepresentation, backup.fileSystemRepresentation) != 0) return -1;
	if (rename(staged.fileSystemRepresentation, dest.fileSystemRepresentation) != 0) {
		int saved = errno;
		if (rename(backup.fileSystemRepresentation, dest.fileSystemRepresentation) != 0) {
			fprintf(stderr, "[ion] update: the previous app is at %s\n", backup.fileSystemRepresentation);
		}
		errno = saved;
		return -1;
	}
	[[NSFileManager defaultManager] removeItemAtPath:backup error:nil];
	return 0;
}

// Root's copy would leave the new bundle owned by root, and every later update would ask
// for a password again, so the copy takes the owner of the bundle it replaces.
static int replaceWithAuthorization(NSString *src, NSString *dest, NSString *staged, NSString *backup) {
	NSString *s = shQuoteCString(src.fileSystemRepresentation);
	NSString *d = shQuoteCString(dest.fileSystemRepresentation);
	NSString *st = shQuoteCString(staged.fileSystemRepresentation);
	NSString *b = shQuoteCString(backup.fileSystemRepresentation);
	NSString *cmd = [NSString stringWithFormat:
		@"/bin/rm -rf %@ %@ && /usr/bin/ditto %@ %@ && "
		 "{ [ ! -e %@ ] || { /usr/sbin/chown -R \"$(/usr/bin/stat -f %%u:%%g %@)\" %@ && /bin/mv -f %@ %@; }; } && "
		 "{ /bin/mv -f %@ %@ || { /bin/mv -f %@ %@; /bin/rm -rf %@; exit 1; }; } && /bin/rm -rf %@",
		st, b, s, st,
		d, d, st, d, b,
		st, d, b, d, st, b];

	NSString *appName = [[dest lastPathComponent] stringByDeletingPathExtension];
	NSString *prompt = [NSString stringWithFormat:@"%@ needs to install an update to %@.",
		appName.length ? appName : @"This application", [dest stringByDeletingLastPathComponent]];
	NSString *script = [NSString stringWithFormat:
		@"do shell script \"%@\" with administrator privileges with prompt \"%@\"",
		appleScriptEscape(cmd), appleScriptEscape(prompt)];

	NSDictionary *errInfo = nil;
	[[[NSAppleScript alloc] initWithSource:script] executeAndReturnError:&errInfo];
	if (!errInfo) return 0;
	NSNumber *code = errInfo[NSAppleScriptErrorNumber];
	if (code && code.intValue == -128) return -3;
	fprintf(stderr, "[ion] update: privileged install of %s failed: %s\n",
		dest.fileSystemRepresentation, [errInfo[NSAppleScriptErrorMessage] description].UTF8String ?: "unknown error");
	return -4;
}

int ionUpdateReplaceApp(const char *srcAppPath, const char *destAppPath) {
	if (!srcAppPath || !destAppPath || !*destAppPath) return -1;
	NSString *src = @(srcAppPath);
	NSString *dest = @(destAppPath);
	NSString *dir = [dest stringByDeletingLastPathComponent];
	NSString *staged = [dir stringByAppendingPathComponent:
		[NSString stringWithFormat:@".%@.ion-update", dest.lastPathComponent]];
	NSString *backup = [staged stringByAppendingString:@".old"];

	if (access(dir.fileSystemRepresentation, W_OK) != 0) {
		if (errno == EACCES || errno == EPERM) {
			int rc = replaceWithAuthorization(src, dest, staged, backup);
			if (rc == 0) utimes(dest.fileSystemRepresentation, NULL);
			return rc;
		}
		fprintf(stderr, "[ion] update: cannot write %s: %s\n", dir.fileSystemRepresentation, strerror(errno));
		return -2;
	}

	NSFileManager *fm = [NSFileManager defaultManager];
	[fm removeItemAtPath:staged error:nil];
	[fm removeItemAtPath:backup error:nil];
	if (runTaskSync(@"/usr/bin/ditto", @[src, staged]) != 0) {
		fprintf(stderr, "[ion] update: cannot copy %s to %s\n", srcAppPath, staged.fileSystemRepresentation);
		[fm removeItemAtPath:staged error:nil];
		return -2;
	}
	if (moveIntoPlace(staged, dest, backup) != 0) {
		fprintf(stderr, "[ion] update: cannot replace %s: %s\n", destAppPath, strerror(errno));
		[fm removeItemAtPath:staged error:nil];
		return -4;
	}
	// Launch Services and Finder read the bundle's modification date to notice the new version.
	utimes(dest.fileSystemRepresentation, NULL);
	return 0;
}

int ionUpdateUnmountDmg(const char *mountPoint) {
	if (!mountPoint) return -1;
	int rc = runTaskSync(@"/usr/bin/hdiutil",
		@[@"detach", @(mountPoint), @"-force"]);
	return rc == 0 ? 0 : -1;
}

int ionUpdateRelaunchAndExit(const char *destAppPath) {
	if (!destAppPath) return -1;

	// Spawn a tiny detached shell that:
	//   1. Polls `kill -0 <pid>` until our process is gone, then
	//   2. /usr/bin/open the freshly installed .app.
	// posix_spawn detaches the child from our process group via the
	// default flags — child reparents to launchd when we _exit below.
	pid_t myPid = getpid();
	NSString *quotedDest = shQuoteCString(destAppPath);
	NSString *script = [NSString stringWithFormat:
		@"while /bin/kill -0 %d 2>/dev/null; do /bin/sleep 0.1; done; "
		 "/usr/bin/open %@",
		myPid, quotedDest];

	const char *shell = "/bin/sh";
	const char *argv[] = { shell, "-c", script.UTF8String, NULL };

	pid_t child = 0;
	int rc = posix_spawn(&child, shell, NULL, NULL,
	                     (char *const *)argv, environ);
	if (rc != 0) return -5;

	// Release the binary lock immediately so the helper's `open` finds the
	// new .app on disk (rm/ditto already ran) and the OS hasn't faulted
	// pages back from a now-deleted executable.
	_exit(0);
}
