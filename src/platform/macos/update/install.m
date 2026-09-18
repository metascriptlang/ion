// Ion macOS — OTA install bridge.
//
// Four primitives, stateless: mount the .dmg, find the .app inside, replace
// the on-disk .app at /Applications (with one admin prompt), detach the
// image, then spawn a detached helper that waits for our pid to die before
// opening the new .app. Caller (std/ion update.ms) does the verify, scoring,
// and progress UX; this file is pure plumbing.
//
// We use AppleScript "do shell script with administrator privileges" as the
// privilege-elevation pipe. The non-deprecated alternative, AuthorizationServices
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

int ionUpdateReplaceApp(const char *srcAppPath, const char *destAppPath) {
	if (!srcAppPath || !destAppPath) return -1;

	// One admin prompt covers both rm + ditto. We delete first so that any
	// stale files / mismatched bundle structure don't survive. `ditto`
	// preserves extended attributes, ACLs, and resource forks — `cp -R`
	// would silently drop quarantine flags and code-signature metadata.
	//
	// Two-stage escaping: paths are sh-quoted (single-quote-safe) before
	// being assembled into a shell command, then the assembled command is
	// AppleScript-escaped before being embedded in the do-shell-script
	// double-quoted argument. Either stage alone leaves an injection hole.
	NSString *src  = shQuoteCString(srcAppPath);
	NSString *dst  = shQuoteCString(destAppPath);
	NSString *cmd  = [NSString stringWithFormat:
		@"/bin/rm -rf %@ && /usr/bin/ditto %@ %@", dst, src, dst];
	NSString *body = appleScriptEscape(cmd);

	NSString *destPath = @(destAppPath);
	NSString *appName  = [[destPath lastPathComponent] stringByDeletingPathExtension];
	NSString *destDir  = [destPath stringByDeletingLastPathComponent];
	if (appName.length == 0) appName = @"This application";
	if (destDir.length == 0) destDir = @"/Applications";
	NSString *prompt = appleScriptEscape([NSString stringWithFormat:
		@"%@ needs to install an update to %@.", appName, destDir]);

	NSString *script = [NSString stringWithFormat:
		@"do shell script \"%@\" "
		 "with administrator privileges "
		 "with prompt \"%@\"",
		body, prompt];

	NSAppleScript *as = [[NSAppleScript alloc] initWithSource:script];
	NSDictionary *errInfo = nil;
	[as executeAndReturnError:&errInfo];
	if (errInfo) {
		// -128 = userCanceledErr (clicked Cancel on the auth dialog).
		NSNumber *code = errInfo[NSAppleScriptErrorNumber];
		if (code && code.intValue == -128) return -3;
		return -4;
	}
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
