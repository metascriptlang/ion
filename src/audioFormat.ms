// Which files Ion plays and records. Pure MetaScript so it is testable without a device.

const playable: string[] = [".wav", ".flac", ".mp3", ".ogg"];

// Lowercase extension with its dot, "" when the file name has none.
export function audioExtension(path: string): string {
	const dot = path.lastIndexOf(".");
	const slash = Math.max(path.lastIndexOf("/"), path.lastIndexOf("\\"));
	if (dot < 0 || dot < slash) { return ""; }
	return path.slice(dot, path.length).toLowerCase();
}

export function checkPlayable(path: string): Result<void, string> {
	const ext = audioExtension(path);
	for (const known of playable) {
		if (known === ext) { return Result.ok(null); }
	}
	const shown = ext === "" ? "(no extension)" : ext;
	return Result.err("unsupported audio format " + shown + " in " + path + "; playable: wav, flac, mp3, ogg");
}

export function checkRecordable(path: string): Result<void, string> {
	const ext = audioExtension(path);
	if (ext === ".wav") { return Result.ok(null); }
	const shown = ext === "" ? "(no extension)" : ext;
	return Result.err("unsupported recording format " + shown + " in " + path + "; recordable: wav");
}
