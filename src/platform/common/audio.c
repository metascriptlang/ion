// Audio for every platform on one miniaudio build: file sounds on a shared engine,
// ring-buffer PCM output and capture streams, and WAV recording. The device threads
// run C only; MetaScript reaches them through the ring buffers and atomic counters.
// Every function returns an id (>= 0) or a non-negative result, or a negative error:
// a miniaudio result code (-1 .. -100) or one of the ION_AUDIO_E_* codes below.

#define STB_VORBIS_HEADER_ONLY
#include "../../../vendor/stb/stb_vorbis.c"
#define MINIAUDIO_IMPLEMENTATION
#include "../../../vendor/miniaudio/miniaudio.h"
#undef STB_VORBIS_HEADER_ONLY
#include "../../../vendor/stb/stb_vorbis.c"

#include <stdio.h>
#include <string.h>

#define ION_AUDIO_E_BAD_HANDLE (-1000)
#define ION_AUDIO_E_NO_SLOT    (-1001)
#define ION_AUDIO_E_BAD_ARGS   (-1002)
#define ION_AUDIO_E_NOT_RUNNING (-1003)
#define ION_AUDIO_E_BAD_STATE  (-1004)

#define MAX_SOUNDS 64
#define MAX_STREAMS 16
#define MAX_RECORDINGS 4
#define PATH_CAP 1024

const char *ionAudioErrorName(int code) {
	switch (code) {
	case ION_AUDIO_E_BAD_HANDLE: return "audio: no such handle";
	case ION_AUDIO_E_NO_SLOT: return "audio: no free slot";
	case ION_AUDIO_E_BAD_ARGS: return "audio: bad arguments";
	case ION_AUDIO_E_NOT_RUNNING: return "audio: device stopped";
	case ION_AUDIO_E_BAD_STATE: return "audio: wrong state for this call";
	}
	return ma_result_description((ma_result)code);
}

#ifdef _WIN32
#include <windows.h>
static int widen(const char *utf8, wchar_t *out, int cap) {
	return MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8, -1, out, cap) > 0;
}
#endif

// ---- sounds ---------------------------------------------------------------

typedef struct {
	int used;
	ma_sound snd;
	ma_uint32 sampleRate;
	ma_uint64 lengthFrames;
	ma_uint32 ended;
	float volume;
	int muted;
} IonSound;

static ma_engine g_engine;
static int g_engineUp;
static IonSound g_sounds[MAX_SOUNDS];

static int engineUp(void) {
	if (g_engineUp) return 0;
	ma_result r = ma_engine_init(NULL, &g_engine);
	if (r != MA_SUCCESS) return (int)r;
	g_engineUp = 1;
	return 0;
}

// miniaudio reads files through its resource manager, where its Vorbis decoder runs in push
// mode and reports length 0; stb_vorbis reads the length from the file itself. The count is
// scaled to `rate`, the frame rate the sound's cursor runs in.
static ma_uint64 vorbisFrames(const char *path, ma_uint32 rate) {
	FILE *f;
#ifdef _WIN32
	wchar_t wide[PATH_CAP];
	if (!widen(path, wide, PATH_CAP)) return 0;
	f = _wfopen(wide, L"rb");
#else
	f = fopen(path, "rb");
#endif
	if (!f) return 0;
	int err = 0;
	stb_vorbis *v = stb_vorbis_open_file(f, 1, &err, NULL);
	if (!v) return 0;
	ma_uint64 frames = (ma_uint64)((double)stb_vorbis_stream_length_in_samples(v) * rate / stb_vorbis_get_info(v).sample_rate);
	stb_vorbis_close(v);
	return frames;
}

static IonSound *soundAt(int id) {
	if (id < 0 || id >= MAX_SOUNDS || !g_sounds[id].used) return NULL;
	return &g_sounds[id];
}

static void soundEnded(void *user, ma_sound *snd) {
	(void)snd;
	ma_atomic_exchange_32(&((IonSound *)user)->ended, 1);
}

static void applyVolume(IonSound *s) {
	ma_sound_set_volume(&s->snd, s->muted ? 0.0f : s->volume);
}

int ionAudioSoundLoad(const char *path) {
	int e = engineUp();
	if (e) return e;
	int id = -1;
	for (int i = 0; i < MAX_SOUNDS; i++) if (!g_sounds[i].used) { id = i; break; }
	if (id < 0) return ION_AUDIO_E_NO_SLOT;
	IonSound *s = &g_sounds[id];
	memset(s, 0, sizeof *s);
	ma_result r;
#ifdef _WIN32
	wchar_t wide[PATH_CAP];
	if (!widen(path, wide, PATH_CAP)) return ION_AUDIO_E_BAD_ARGS;
	r = ma_sound_init_from_file_w(&g_engine, wide, MA_SOUND_FLAG_STREAM, NULL, NULL, &s->snd);
#else
	r = ma_sound_init_from_file(&g_engine, path, MA_SOUND_FLAG_STREAM, NULL, NULL, &s->snd);
#endif
	if (r != MA_SUCCESS) return (int)r;
	ma_sound_get_data_format(&s->snd, NULL, NULL, &s->sampleRate, NULL, 0);
	ma_sound_get_length_in_pcm_frames(&s->snd, &s->lengthFrames);
	if (s->lengthFrames == 0) s->lengthFrames = vorbisFrames(path, s->sampleRate);
	s->volume = 1.0f;
	ma_sound_set_end_callback(&s->snd, soundEnded, s);
	s->used = 1;
	return id;
}

int ionAudioSoundUnload(int id) {
	IonSound *s = soundAt(id);
	if (!s) return ION_AUDIO_E_BAD_HANDLE;
	ma_sound_uninit(&s->snd);
	s->used = 0;
	return 0;
}

int ionAudioSoundPlay(int id) {
	IonSound *s = soundAt(id);
	if (!s) return ION_AUDIO_E_BAD_HANDLE;
	if (ma_sound_at_end(&s->snd)) ma_sound_seek_to_pcm_frame(&s->snd, 0);
	ma_atomic_exchange_32(&s->ended, 0);
	return (int)ma_sound_start(&s->snd);
}

int ionAudioSoundPause(int id) {
	IonSound *s = soundAt(id);
	if (!s) return ION_AUDIO_E_BAD_HANDLE;
	return (int)ma_sound_stop(&s->snd);
}

int ionAudioSoundStop(int id) {
	IonSound *s = soundAt(id);
	if (!s) return ION_AUDIO_E_BAD_HANDLE;
	ma_result r = ma_sound_stop(&s->snd);
	if (r != MA_SUCCESS) return (int)r;
	ma_atomic_exchange_32(&s->ended, 0);
	return (int)ma_sound_seek_to_pcm_frame(&s->snd, 0);
}

int ionAudioSoundSeek(int id, double ms) {
	IonSound *s = soundAt(id);
	if (!s) return ION_AUDIO_E_BAD_HANDLE;
	if (ms < 0) return ION_AUDIO_E_BAD_ARGS;
	return (int)ma_sound_seek_to_pcm_frame(&s->snd, (ma_uint64)(ms * s->sampleRate / 1000.0));
}

int ionAudioSoundSetVolume(int id, double volume) {
	IonSound *s = soundAt(id);
	if (!s) return ION_AUDIO_E_BAD_HANDLE;
	if (volume < 0) return ION_AUDIO_E_BAD_ARGS;
	s->volume = (float)volume;
	applyVolume(s);
	return 0;
}

int ionAudioSoundSetMuted(int id, int muted) {
	IonSound *s = soundAt(id);
	if (!s) return ION_AUDIO_E_BAD_HANDLE;
	s->muted = muted != 0;
	applyVolume(s);
	return 0;
}

int ionAudioSoundSetLooping(int id, int looping) {
	IonSound *s = soundAt(id);
	if (!s) return ION_AUDIO_E_BAD_HANDLE;
	ma_sound_set_looping(&s->snd, looping != 0);
	return 0;
}

// Rate is miniaudio's pitch: speed and pitch move together, there is no time-stretch.
int ionAudioSoundSetRate(int id, double rate) {
	IonSound *s = soundAt(id);
	if (!s) return ION_AUDIO_E_BAD_HANDLE;
	if (rate <= 0) return ION_AUDIO_E_BAD_ARGS;
	ma_sound_set_pitch(&s->snd, (float)rate);
	return 0;
}

int ionAudioSoundPlaying(int id) {
	IonSound *s = soundAt(id);
	if (!s) return ION_AUDIO_E_BAD_HANDLE;
	return ma_sound_is_playing(&s->snd) && !ma_sound_at_end(&s->snd);
}

// 1 once after the sound reached its end, then 0 until it ends again.
int ionAudioSoundFinished(int id) {
	IonSound *s = soundAt(id);
	if (!s) return ION_AUDIO_E_BAD_HANDLE;
	return (int)ma_atomic_exchange_32(&s->ended, 0);
}

int ionAudioSoundLooping(int id) {
	IonSound *s = soundAt(id);
	if (!s) return ION_AUDIO_E_BAD_HANDLE;
	return ma_sound_is_looping(&s->snd) ? 1 : 0;
}

int ionAudioSoundMuted(int id) {
	IonSound *s = soundAt(id);
	return s ? s->muted : ION_AUDIO_E_BAD_HANDLE;
}

double ionAudioSoundVolume(int id) {
	IonSound *s = soundAt(id);
	return s ? s->volume : 0.0;
}

double ionAudioSoundRate(int id) {
	IonSound *s = soundAt(id);
	return s ? ma_sound_get_pitch(&s->snd) : 0.0;
}

double ionAudioSoundPositionMs(int id) {
	IonSound *s = soundAt(id);
	ma_uint64 frames = 0;
	if (!s || ma_sound_get_cursor_in_pcm_frames(&s->snd, &frames) != MA_SUCCESS) return 0.0;
	return frames * 1000.0 / s->sampleRate;
}

double ionAudioSoundDurationMs(int id) {
	IonSound *s = soundAt(id);
	return s ? s->lengthFrames * 1000.0 / s->sampleRate : 0.0;
}

// ---- PCM streams (output and capture) ---------------------------------------

typedef struct {
	int used;
	int capture;
	int channels;
	int sampleRate;
	int bufferFrames;
	ma_device dev;
	ma_pcm_rb rb;
	ma_uint32 started;   // output: the device runs once the ring holds one buffer
	ma_uint32 draining;
	ma_uint32 missed;    // output underruns, capture overruns
} IonStream;

static IonStream g_streams[MAX_STREAMS];

static IonStream *streamAt(int id, int capture) {
	if (id < 0 || id >= MAX_STREAMS || !g_streams[id].used || g_streams[id].capture != capture) return NULL;
	return &g_streams[id];
}

static void outputCallback(ma_device *dev, void *out, const void *in, ma_uint32 frames) {
	IonStream *st = (IonStream *)dev->pUserData;
	ma_uint32 done = 0;
	(void)in;
	while (done < frames) {
		ma_uint32 n = frames - done;
		void *src;
		if (ma_pcm_rb_acquire_read(&st->rb, &n, &src) != MA_SUCCESS || n == 0) break;
		memcpy((float *)out + (size_t)done * st->channels, src, (size_t)n * st->channels * sizeof(float));
		ma_pcm_rb_commit_read(&st->rb, n);
		done += n;
	}
	if (done < frames) {
		memset((float *)out + (size_t)done * st->channels, 0, (size_t)(frames - done) * st->channels * sizeof(float));
		if (!ma_atomic_load_32(&st->draining)) ma_atomic_fetch_add_32(&st->missed, 1);
	}
}

static void captureCallback(ma_device *dev, void *out, const void *in, ma_uint32 frames) {
	IonStream *st = (IonStream *)dev->pUserData;
	ma_uint32 done = 0;
	(void)out;
	while (done < frames) {
		ma_uint32 n = frames - done;
		void *dst;
		if (ma_pcm_rb_acquire_write(&st->rb, &n, &dst) != MA_SUCCESS || n == 0) break;
		memcpy(dst, (const float *)in + (size_t)done * st->channels, (size_t)n * st->channels * sizeof(float));
		ma_pcm_rb_commit_write(&st->rb, n);
		done += n;
	}
	if (done < frames) ma_atomic_fetch_add_32(&st->missed, 1);
}

static int streamOpen(int capture, int sampleRate, int channels, int bufferFrames) {
	if (sampleRate <= 0 || channels <= 0 || channels > 8 || bufferFrames <= 0) return ION_AUDIO_E_BAD_ARGS;
	int id = -1;
	for (int i = 0; i < MAX_STREAMS; i++) if (!g_streams[i].used) { id = i; break; }
	if (id < 0) return ION_AUDIO_E_NO_SLOT;
	IonStream *st = &g_streams[id];
	memset(st, 0, sizeof *st);
	st->capture = capture;
	st->channels = channels;
	st->sampleRate = sampleRate;
	st->bufferFrames = bufferFrames;
	ma_result r = ma_pcm_rb_init(ma_format_f32, (ma_uint32)channels, (ma_uint32)bufferFrames * 4, NULL, NULL, &st->rb);
	if (r != MA_SUCCESS) return (int)r;
	ma_device_config cfg = ma_device_config_init(capture ? ma_device_type_capture : ma_device_type_playback);
	if (capture) { cfg.capture.format = ma_format_f32; cfg.capture.channels = (ma_uint32)channels; }
	else { cfg.playback.format = ma_format_f32; cfg.playback.channels = (ma_uint32)channels; }
	cfg.sampleRate = (ma_uint32)sampleRate;
	cfg.periodSizeInFrames = (ma_uint32)bufferFrames;
	cfg.dataCallback = capture ? captureCallback : outputCallback;
	cfg.pUserData = st;
	r = ma_device_init(NULL, &cfg, &st->dev);
	if (r != MA_SUCCESS) { ma_pcm_rb_uninit(&st->rb); return (int)r; }
	if (capture) {
		r = ma_device_start(&st->dev);
		if (r != MA_SUCCESS) { ma_device_uninit(&st->dev); ma_pcm_rb_uninit(&st->rb); return (int)r; }
		st->started = 1;
	}
	st->used = 1;
	return id;
}

static int streamClose(IonStream *st) {
	ma_device_uninit(&st->dev);
	ma_pcm_rb_uninit(&st->rb);
	st->used = 0;
	return 0;
}

int ionAudioOutOpen(int sampleRate, int channels, int bufferFrames) {
	return streamOpen(0, sampleRate, channels, bufferFrames);
}

// Blocks while the ring is full. The device starts once one buffer is queued, so the
// first callbacks never count as underruns.
int ionAudioOutWrite(int id, const float *samples, int frames) {
	IonStream *st = streamAt(id, 0);
	if (!st) return ION_AUDIO_E_BAD_HANDLE;
	if (frames < 0) return ION_AUDIO_E_BAD_ARGS;
	ma_uint32 done = 0;
	while (done < (ma_uint32)frames) {
		ma_uint32 n = (ma_uint32)frames - done;
		void *dst;
		ma_result r = ma_pcm_rb_acquire_write(&st->rb, &n, &dst);
		if (r != MA_SUCCESS) return (int)r;
		if (n == 0) {
			if (st->started && ma_device_get_state(&st->dev) != ma_device_state_started) return ION_AUDIO_E_NOT_RUNNING;
			ma_sleep(2);
			continue;
		}
		memcpy(dst, samples + (size_t)done * st->channels, (size_t)n * st->channels * sizeof(float));
		ma_pcm_rb_commit_write(&st->rb, n);
		done += n;
		if (!st->started && ma_pcm_rb_available_read(&st->rb) >= (ma_uint32)st->bufferFrames) {
			r = ma_device_start(&st->dev);
			if (r != MA_SUCCESS) return (int)r;
			st->started = 1;
		}
	}
	return 0;
}

int ionAudioOutUnderruns(int id) {
	IonStream *st = streamAt(id, 0);
	return st ? (int)ma_atomic_load_32(&st->missed) : ION_AUDIO_E_BAD_HANDLE;
}

// Lets the queued frames play out (bounded by the ring's length) before the device stops.
int ionAudioOutClose(int id) {
	IonStream *st = streamAt(id, 0);
	if (!st) return ION_AUDIO_E_BAD_HANDLE;
	if (!st->started && ma_pcm_rb_available_read(&st->rb) > 0 && ma_device_start(&st->dev) == MA_SUCCESS) st->started = 1;
	ma_atomic_exchange_32(&st->draining, 1);
	if (st->started) {
		for (int waited = 0; ma_pcm_rb_available_read(&st->rb) > 0 && waited < 2000; waited += 5) ma_sleep(5);
		ma_sleep(60);
	}
	return streamClose(st);
}

int ionAudioInOpen(int sampleRate, int channels, int bufferFrames) {
	return streamOpen(1, sampleRate, channels, bufferFrames);
}

// Blocks until `frames` frames are read.
int ionAudioInRead(int id, float *out, int frames) {
	IonStream *st = streamAt(id, 1);
	if (!st) return ION_AUDIO_E_BAD_HANDLE;
	if (frames < 0) return ION_AUDIO_E_BAD_ARGS;
	ma_uint32 done = 0;
	while (done < (ma_uint32)frames) {
		ma_uint32 n = (ma_uint32)frames - done;
		void *src;
		ma_result r = ma_pcm_rb_acquire_read(&st->rb, &n, &src);
		if (r != MA_SUCCESS) return (int)r;
		if (n == 0) {
			if (ma_device_get_state(&st->dev) != ma_device_state_started) return ION_AUDIO_E_NOT_RUNNING;
			ma_sleep(2);
			continue;
		}
		memcpy(out + (size_t)done * st->channels, src, (size_t)n * st->channels * sizeof(float));
		ma_pcm_rb_commit_read(&st->rb, n);
		done += n;
	}
	return 0;
}

int ionAudioInOverruns(int id) {
	IonStream *st = streamAt(id, 1);
	return st ? (int)ma_atomic_load_32(&st->missed) : ION_AUDIO_E_BAD_HANDLE;
}

int ionAudioInClose(int id) {
	IonStream *st = streamAt(id, 1);
	if (!st) return ION_AUDIO_E_BAD_HANDLE;
	return streamClose(st);
}

// ---- WAV recording ----------------------------------------------------------
// The device callback writes the encoder's file itself, so a slow disk can drop input.

typedef struct {
	int used;
	int live;            // device and encoder exist
	int sampleRate;
	ma_device dev;
	ma_encoder enc;
	ma_uint32 paused;
	ma_uint64 frames;
	char path[PATH_CAP];
} IonRecording;

static IonRecording g_recs[MAX_RECORDINGS];

static IonRecording *recAt(int id) {
	if (id < 0 || id >= MAX_RECORDINGS || !g_recs[id].used) return NULL;
	return &g_recs[id];
}

static void recordCallback(ma_device *dev, void *out, const void *in, ma_uint32 frames) {
	IonRecording *rec = (IonRecording *)dev->pUserData;
	ma_uint64 written = 0;
	(void)out;
	if (ma_atomic_load_32(&rec->paused)) return;
	ma_encoder_write_pcm_frames(&rec->enc, in, frames, &written);
	ma_atomic_fetch_add_64(&rec->frames, written);
}

int ionAudioRecordStart(const char *path, int sampleRate, int channels) {
	if (sampleRate <= 0 || channels <= 0 || channels > 8 || strlen(path) >= PATH_CAP) return ION_AUDIO_E_BAD_ARGS;
	int id = -1;
	for (int i = 0; i < MAX_RECORDINGS; i++) if (!g_recs[i].used) { id = i; break; }
	if (id < 0) return ION_AUDIO_E_NO_SLOT;
	IonRecording *rec = &g_recs[id];
	memset(rec, 0, sizeof *rec);
	strcpy(rec->path, path);
	rec->sampleRate = sampleRate;
	ma_encoder_config ecfg = ma_encoder_config_init(ma_encoding_format_wav, ma_format_s16, (ma_uint32)channels, (ma_uint32)sampleRate);
	ma_result r;
#ifdef _WIN32
	wchar_t wide[PATH_CAP];
	if (!widen(path, wide, PATH_CAP)) return ION_AUDIO_E_BAD_ARGS;
	r = ma_encoder_init_file_w(wide, &ecfg, &rec->enc);
#else
	r = ma_encoder_init_file(path, &ecfg, &rec->enc);
#endif
	if (r != MA_SUCCESS) return (int)r;
	ma_device_config cfg = ma_device_config_init(ma_device_type_capture);
	cfg.capture.format = ma_format_s16;
	cfg.capture.channels = (ma_uint32)channels;
	cfg.sampleRate = (ma_uint32)sampleRate;
	cfg.dataCallback = recordCallback;
	cfg.pUserData = rec;
	r = ma_device_init(NULL, &cfg, &rec->dev);
	if (r != MA_SUCCESS) { ma_encoder_uninit(&rec->enc); return (int)r; }
	r = ma_device_start(&rec->dev);
	if (r != MA_SUCCESS) { ma_device_uninit(&rec->dev); ma_encoder_uninit(&rec->enc); return (int)r; }
	rec->live = 1;
	rec->used = 1;
	return id;
}

int ionAudioRecordPause(int id) {
	IonRecording *rec = recAt(id);
	if (!rec) return ION_AUDIO_E_BAD_HANDLE;
	if (!rec->live) return ION_AUDIO_E_BAD_STATE;
	ma_atomic_exchange_32(&rec->paused, 1);
	return 0;
}

int ionAudioRecordResume(int id) {
	IonRecording *rec = recAt(id);
	if (!rec) return ION_AUDIO_E_BAD_HANDLE;
	if (!rec->live) return ION_AUDIO_E_BAD_STATE;
	ma_atomic_exchange_32(&rec->paused, 0);
	return 0;
}

static void recTeardown(IonRecording *rec) {
	if (!rec->live) return;
	ma_device_uninit(&rec->dev);
	ma_encoder_uninit(&rec->enc);
	rec->live = 0;
}

// Finalises the file; the handle keeps answering status until ionAudioRecordClose.
int ionAudioRecordStop(int id) {
	IonRecording *rec = recAt(id);
	if (!rec) return ION_AUDIO_E_BAD_HANDLE;
	recTeardown(rec);
	return 0;
}

int ionAudioRecordClose(int id) {
	IonRecording *rec = recAt(id);
	if (!rec) return ION_AUDIO_E_BAD_HANDLE;
	recTeardown(rec);
	rec->used = 0;
	return 0;
}

// 1 while capturing into the file (live and not paused).
int ionAudioRecordRecording(int id) {
	IonRecording *rec = recAt(id);
	if (!rec) return ION_AUDIO_E_BAD_HANDLE;
	return rec->live && !ma_atomic_load_32(&rec->paused);
}

double ionAudioRecordDurationMs(int id) {
	IonRecording *rec = recAt(id);
	return rec ? ma_atomic_load_64(&rec->frames) * 1000.0 / rec->sampleRate : 0.0;
}

const char *ionAudioRecordPath(int id) {
	IonRecording *rec = recAt(id);
	return rec ? rec->path : "";
}
