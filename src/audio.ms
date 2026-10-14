// Audio: file sounds, PCM streams and WAV recording on the default devices.
//
// Playback decodes wav, flac, mp3 and ogg vorbis; recording writes 16-bit WAV. Any other
// extension is an error that names it. Streams are ring buffers: the device thread never
// runs MetaScript, a blocking read or write on this thread is the whole contract.
// Every miniaudio failure comes back as an error string; nothing is swallowed.
//
// Status is polled: `soundStatus` reports `finished` once after a sound ends. The wake
// call for an idle loop belongs in the sound end callback in common/audio.c.

// Build directives live here, not in ipc.ms: an app that only plays sound must not pull in
// the window host or its GUI subsystem flag. The compiler dedupes this file with any other
// @compile of it.
@compile("./platform/common/audio.c");

when (macos) {
	@passL("-framework CoreFoundation");
	@passL("-framework CoreAudio");
	@passL("-framework AudioToolbox");
}

when (linux) {
	// miniaudio opens PulseAudio and ALSA with dlopen.
	@passL("-ldl");
	@passL("-lpthread");
	@passL("-lm");
}

import {
	ionAudioErrorName,
	ionAudioSoundLoad, ionAudioSoundUnload, ionAudioSoundPlay, ionAudioSoundPause, ionAudioSoundStop,
	ionAudioSoundSeek, ionAudioSoundSetVolume, ionAudioSoundSetMuted, ionAudioSoundSetLooping, ionAudioSoundSetRate,
	ionAudioSoundPlaying, ionAudioSoundFinished, ionAudioSoundLooping, ionAudioSoundMuted,
	ionAudioSoundVolume, ionAudioSoundRate, ionAudioSoundPositionMs, ionAudioSoundDurationMs,
	ionAudioOutOpen, ionAudioOutWrite, ionAudioOutUnderruns, ionAudioOutClose,
	ionAudioInOpen, ionAudioInRead, ionAudioInOverruns, ionAudioInClose,
	ionAudioRecordStart, ionAudioRecordPause, ionAudioRecordResume, ionAudioRecordStop, ionAudioRecordClose,
	ionAudioRecordRecording, ionAudioRecordDurationMs, ionAudioRecordPath,
} from "./platform/bridge.h";
import { checkPlayable, checkRecordable } from "./audioFormat";

export struct SoundStatus {
	playing: boolean;
	positionMs: number;
	durationMs: number;
	finished: boolean;
	looping: boolean;
	volume: number;
	muted: boolean;
	rate: number;
}

export struct RecordingStatus {
	recording: boolean;
	durationMs: number;
	path: string;
}

// A PCM stream handle: the native id and the channel count that sizes every buffer.
export struct PcmStream {
	id: int32;
	channels: int32;
}

function failed(api: string, code: int32): string {
	return api + ": " + ionAudioErrorName(code);
}

function done(api: string, code: int32): Result<void, string> {
	if (code < 0) { return Result.err(failed(api, code)); }
	return Result.ok(null);
}

function idOr(api: string, code: int32): Result<int32, string> {
	if (code < 0) { return Result.err(failed(api, code)); }
	return Result.ok(code);
}

// ---- sounds -------------------------------------------------------------

export function loadSound(path: string): Result<int32, string> {
	const ok = try checkPlayable(path);
	return idOr("loadSound " + path, ionAudioSoundLoad(path));
}

export function unloadSound(id: int32): Result<void, string> { return done("unloadSound", ionAudioSoundUnload(id)); }
export function playSound(id: int32): Result<void, string> { return done("playSound", ionAudioSoundPlay(id)); }
export function pauseSound(id: int32): Result<void, string> { return done("pauseSound", ionAudioSoundPause(id)); }
export function stopSound(id: int32): Result<void, string> { return done("stopSound", ionAudioSoundStop(id)); }
export function seekSound(id: int32, ms: number): Result<void, string> { return done("seekSound", ionAudioSoundSeek(id, ms)); }
export function setSoundVolume(id: int32, volume: number): Result<void, string> { return done("setSoundVolume", ionAudioSoundSetVolume(id, volume)); }
export function setSoundMuted(id: int32, muted: boolean): Result<void, string> { return done("setSoundMuted", ionAudioSoundSetMuted(id, muted ? 1 : 0)); }
export function setSoundLooping(id: int32, looping: boolean): Result<void, string> { return done("setSoundLooping", ionAudioSoundSetLooping(id, looping ? 1 : 0)); }

// Rate is pitch: speed and pitch change together, there is no time-stretch.
export function setSoundRate(id: int32, rate: number): Result<void, string> { return done("setSoundRate", ionAudioSoundSetRate(id, rate)); }

// `finished` is true once after the sound reaches its end, then false until it ends again.
export function soundStatus(id: int32): Result<SoundStatus, string> {
	const playing = ionAudioSoundPlaying(id);
	if (playing < 0) { return Result.err(failed("soundStatus", playing)); }
	return Result.ok({
		playing: playing === 1,
		positionMs: ionAudioSoundPositionMs(id),
		durationMs: ionAudioSoundDurationMs(id),
		finished: ionAudioSoundFinished(id) === 1,
		looping: ionAudioSoundLooping(id) === 1,
		volume: ionAudioSoundVolume(id),
		muted: ionAudioSoundMuted(id) === 1,
		rate: ionAudioSoundRate(id),
	});
}

// ---- PCM streams --------------------------------------------------------

export function openAudioOutput(sampleRate: int32, channels: int32, bufferFrames: int32): Result<PcmStream, string> {
	const id = try idOr("openAudioOutput", ionAudioOutOpen(sampleRate, channels, bufferFrames));
	return Result.ok({ id, channels });
}

// Interleaved f32 samples; blocks while the ring buffer is full.
export function writeAudioOutput(stream: PcmStream, samples: float32[]): Result<void, string> {
	if (samples.length === 0) { return Result.ok(null); }
	if (samples.length % stream.channels !== 0) {
		return Result.err("writeAudioOutput: " + samples.length.toString() + " samples is not a whole number of " + stream.channels.toString() + "-channel frames");
	}
	return done("writeAudioOutput", ionAudioOutWrite(stream.id, samples[0], samples.length / stream.channels));
}

// Callbacks that found the ring buffer short, after the first buffer was queued.
export function audioOutputUnderruns(stream: PcmStream): Result<int32, string> {
	return idOr("audioOutputUnderruns", ionAudioOutUnderruns(stream.id));
}

export function closeAudioOutput(stream: PcmStream): Result<void, string> { return done("closeAudioOutput", ionAudioOutClose(stream.id)); }

export function openAudioInput(sampleRate: int32, channels: int32, bufferFrames: int32): Result<PcmStream, string> {
	const id = try idOr("openAudioInput", ionAudioInOpen(sampleRate, channels, bufferFrames));
	return Result.ok({ id, channels });
}

// Fills `out` with interleaved f32 samples; blocks until it is full.
export function readAudioInput(stream: PcmStream, out: float32[]): Result<void, string> {
	if (out.length === 0) { return Result.ok(null); }
	if (out.length % stream.channels !== 0) {
		return Result.err("readAudioInput: " + out.length.toString() + " samples is not a whole number of " + stream.channels.toString() + "-channel frames");
	}
	return done("readAudioInput", ionAudioInRead(stream.id, out[0], out.length / stream.channels));
}

// Callbacks that found the ring buffer full: the frames were dropped.
export function audioInputOverruns(stream: PcmStream): Result<int32, string> {
	return idOr("audioInputOverruns", ionAudioInOverruns(stream.id));
}

export function closeAudioInput(stream: PcmStream): Result<void, string> { return done("closeAudioInput", ionAudioInClose(stream.id)); }

// ---- recording ----------------------------------------------------------

// Starts capturing the default input into a 16-bit WAV at `path`.
export function startRecording(path: string, sampleRate: int32, channels: int32): Result<int32, string> {
	const ok = try checkRecordable(path);
	return idOr("startRecording " + path, ionAudioRecordStart(path, sampleRate, channels));
}

export function pauseRecording(id: int32): Result<void, string> { return done("pauseRecording", ionAudioRecordPause(id)); }
export function resumeRecording(id: int32): Result<void, string> { return done("resumeRecording", ionAudioRecordResume(id)); }

// Finalises the WAV; the handle keeps answering `recordingStatus` until `closeRecording`.
export function stopRecording(id: int32): Result<void, string> { return done("stopRecording", ionAudioRecordStop(id)); }
export function closeRecording(id: int32): Result<void, string> { return done("closeRecording", ionAudioRecordClose(id)); }

export function recordingStatus(id: int32): Result<RecordingStatus, string> {
	const recording = ionAudioRecordRecording(id);
	if (recording < 0) { return Result.err(failed("recordingStatus", recording)); }
	return Result.ok({
		recording: recording === 1,
		durationMs: ionAudioRecordDurationMs(id),
		path: ionAudioRecordPath(id),
	});
}
