// Audio on the default devices: record 2 s to a WAV, play it back through the sound API,
// stream a 440 Hz sine from MetaScript through a ring buffer, and refuse an m4a.
//
// Usage:
//   msc build examples/audio.ms
//   out/debug/audio.exe
//
// audio.ms owns its own build directives, so this app has no window host.
import {
	startRecording, stopRecording, recordingStatus, closeRecording,
	loadSound, playSound, seekSound, setSoundVolume, setSoundLooping, setSoundRate, soundStatus, unloadSound,
	openAudioOutput, writeAudioOutput, audioOutputUnderruns, closeAudioOutput,
} from "../src/audio";
import { ensureDir, fileSize } from "std/fs";

const wavPath = "out/rec.wav";

// No sleep exists outside the event loop, so a measurement spins on the monotonic clock.
function waitMs(ms: number): void {
	const until = performance.now() + ms;
	while (performance.now() < until) {}
}

function fail(what: string, message: string): int32 {
	console.log(`FAIL ${what}: ${message}`);
	return 1 as int32;
}

function record(): int32 {
	const id = try startRecording(wavPath, 48000, 1) catch -1;
	if (id < 0) { return fail("startRecording", "no capture device or permission, see error below"); }
	while (true) {
		const st = recordingStatus(id);
		if (!st.ok) { return fail("recordingStatus", st.error); }
		if (st.value.durationMs >= 2000) { break; }
	}
	const stopped = stopRecording(id);
	if (!stopped.ok) { return fail("stopRecording", stopped.error); }
	const st = recordingStatus(id);
	if (st.ok) { console.log(`recording: recording=${st.value.recording} durationMs=${st.value.durationMs} path=${st.value.path} fileBytes=${fileSize(wavPath)}`); }
	closeRecording(id);
	return 0 as int32;
}

function playBack(): int32 {
	const loaded = loadSound(wavPath);
	if (!loaded.ok) { return fail("loadSound", loaded.error); }
	const id = loaded.value;
	const first = soundStatus(id);
	if (first.ok) { console.log(`loaded: durationMs=${first.value.durationMs} playing=${first.value.playing} volume=${first.value.volume} rate=${first.value.rate}`); }
	setSoundVolume(id, 0.5);
	setSoundLooping(id, true);
	setSoundRate(id, 1.0);
	playSound(id);
	waitMs(300);
	const mid = soundStatus(id);
	if (mid.ok) { console.log(`playing: playing=${mid.value.playing} positionMs=${mid.value.positionMs} looping=${mid.value.looping} volume=${mid.value.volume}`); }
	seekSound(id, 1200);
	const seeked = soundStatus(id);
	if (seeked.ok) { console.log(`after seek 1200: positionMs=${seeked.value.positionMs}`); }
	setSoundLooping(id, false);
	let finishedSeen = 0;
	const deadline = performance.now() + 4000;
	while (performance.now() < deadline) {
		const st = soundStatus(id);
		if (!st.ok) { return fail("soundStatus", st.error); }
		if (st.value.finished) {
			finishedSeen += 1;
			console.log(`finished: playing=${st.value.playing} positionMs=${st.value.positionMs} durationMs=${st.value.durationMs}`);
		}
	}
	console.log(`finished flipped true ${finishedSeen} time(s)`);
	unloadSound(id);
	return 0 as int32;
}

function sine(): int32 {
	const opened = openAudioOutput(48000, 1, 1024);
	if (!opened.ok) { return fail("openAudioOutput", opened.error); }
	const out = opened.value;
	const chunk: float32[] = [];
	for (let i = 0; i < 1024; i++) { chunk.push(0.0 as float32); }
	let phase = 0.0;
	const step = 2.0 * 3.141592653589793 * 440.0 / 48000.0;
	const started = performance.now();
	for (let c = 0; c < 94; c++) {
		for (let i = 0; i < 1024; i++) {
			chunk[i] = (Math.sin(phase) * 0.2) as float32;
			phase += step;
		}
		const w = writeAudioOutput(out, chunk);
		if (!w.ok) { return fail("writeAudioOutput", w.error); }
	}
	const underruns = audioOutputUnderruns(out);
	if (underruns.ok) { console.log(`sine: 94 x 1024 frames at 48000 Hz written in ${performance.now() - started} ms, underruns=${underruns.value}`); }
	closeAudioOutput(out);
	return 0 as int32;
}

function main(): int32 {
	ensureDir("out");
	let bad = 0;
	bad += record();
	bad += playBack();
	bad += sine();
	const m4a = loadSound("x.m4a");
	if (!m4a.ok) { console.log(`m4a: ${m4a.error}`); } else { bad += fail("m4a", "loaded"); }
	console.log(bad === 0 ? "audio example: ok" : "audio example: FAILED");
	return bad as int32;
}

main();
