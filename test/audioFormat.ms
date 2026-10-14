// Tests for src/audioFormat.ms: the playable and recordable extension sets.

import { audioExtension, checkPlayable, checkRecordable } from "../src/audioFormat";

test "extension is lowercased with its dot" {
	assert audioExtension("a/b/Song.MP3") === ".mp3";
}

test "a dot in a directory is not an extension" {
	assert audioExtension("my.dir/song") === "";
}

test "playable formats pass" {
	for (const p of ["a.wav", "a.flac", "a.mp3", "a.ogg", "A.OGG"]) {
		const r = checkPlayable(p);
		assert r.ok;
	}
}

test "m4a is refused with a message naming it" {
	const r = checkPlayable("x.m4a");
	if (r.ok) { assert false; } else { assert r.error.includes(".m4a"); }
}

test "no extension is refused" {
	const r = checkPlayable("noext");
	assert !r.ok;
}

test "recording accepts wav only" {
	assert checkRecordable("out/rec.wav").ok;
	const r = checkRecordable("rec.mp3");
	if (r.ok) { assert false; } else { assert r.error.includes(".mp3"); }
}
