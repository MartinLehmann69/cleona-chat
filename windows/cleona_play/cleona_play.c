// cleona-play -- plays ONE Ogg Vorbis file once on the default output device
// and exits. The Windows counterpart of `pw-play`/`paplay` under Linux: the
// daemon starts one process per sound and ends a loop by ending the process
// (lib/core/service/notification_sound_service.dart).
//
// Why a helper program and not a DLL inside the daemon: the decoder is the
// part that reads foreign input (the user's own sound file, v4_2 §22.8). A
// fault in it ends this throw-away process, not the process that holds the
// keys. Two sounds at once mix, because each one is its own process.
//
// Usage:   cleona-play <file.ogg> [--volume <0..1>] [--check]
//   --volume  linear gain applied to the decoded samples, default 1.0
//   --check   decode only, do not open an output device (bundle self-test,
//             and the only mode on platforms other than Windows)
//
// Exit codes (the daemon logs them, the E2E sound test asserts on 0):
//   0  played to the end (or decoded to the end with --check)
//   2  usage error
//   3  file cannot be opened
//   4  not an Ogg Vorbis stream, or a decode error
//   5  the output device refused the sound (PlaySound returned FALSE)
//   6  format not supported: channel count, sample rate, or longer than the cap
//   7  out of memory
//
// Decoder: libogg + libvorbis (Xiph, BSD-3-Clause), pinned in CMakeLists.txt.
// Output: PlaySound with an in-memory WAV image (winmm) -- no device code of
// our own. PlaySound documentation:
// https://learn.microsoft.com/windows/win32/api/playsoundapi/nf-playsoundapi-playsound

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <mmsystem.h>
#include <shellapi.h>
#endif

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// The header would otherwise give this file four static callback tables, three
// of them unused. The one table needed is defined below.
#define OV_EXCLUDE_STATIC_CALLBACKS
#include <vorbis/codec.h>
#include <vorbis/vorbisfile.h>

enum {
  kExitOk = 0,
  kExitUsage = 2,
  kExitOpen = 3,
  kExitDecode = 4,
  kExitDevice = 5,
  kExitFormat = 6,
  kExitMemory = 7,
};

// A notification sound is seconds long. The cap bounds what a hostile or
// broken file can make this process allocate: 32 MiB of 16-bit PCM is about
// 174 s of 48 kHz stereo.
#define CLEONA_PLAY_MAX_PCM_BYTES ((size_t)32 * 1024 * 1024)
#define CLEONA_PLAY_WAV_HEADER_BYTES 44

static void put_u16(uint8_t* p, uint32_t v) {
  p[0] = (uint8_t)(v & 0xff);
  p[1] = (uint8_t)((v >> 8) & 0xff);
}

static void put_u32(uint8_t* p, uint32_t v) {
  p[0] = (uint8_t)(v & 0xff);
  p[1] = (uint8_t)((v >> 8) & 0xff);
  p[2] = (uint8_t)((v >> 16) & 0xff);
  p[3] = (uint8_t)((v >> 24) & 0xff);
}

// Canonical 44-byte header of a PCM WAV file: RIFF chunk, `fmt ` chunk with
// format tag 1 (PCM), `data` chunk.
static void write_wav_header(uint8_t* h, uint32_t pcm_bytes, uint32_t channels,
                             uint32_t rate) {
  const uint32_t block_align = channels * 2;
  memcpy(h, "RIFF", 4);
  put_u32(h + 4, 36 + pcm_bytes);
  memcpy(h + 8, "WAVE", 4);
  memcpy(h + 12, "fmt ", 4);
  put_u32(h + 16, 16);
  put_u16(h + 20, 1);
  put_u16(h + 22, channels);
  put_u32(h + 24, rate);
  put_u32(h + 28, rate * block_align);
  put_u16(h + 32, block_align);
  put_u16(h + 34, 16);
  memcpy(h + 36, "data", 4);
  put_u32(h + 40, pcm_bytes);
}

static void apply_volume(uint8_t* pcm, size_t pcm_bytes, double volume) {
  if (volume >= 1.0) return;
  // Fixed point, 16 fractional bits; the samples are little-endian int16.
  const int32_t gain = (int32_t)(volume * 65536.0 + 0.5);
  for (size_t i = 0; i + 1 < pcm_bytes; i += 2) {
    const int16_t s = (int16_t)((uint16_t)pcm[i] | ((uint16_t)pcm[i + 1] << 8));
    const int32_t scaled = ((int32_t)s * gain) / 65536;
    pcm[i] = (uint8_t)(scaled & 0xff);
    pcm[i + 1] = (uint8_t)((scaled >> 8) & 0xff);
  }
}

static size_t read_from_file(void* target, size_t size, size_t count,
                             void* file) {
  return fread(target, size, count, (FILE*)file);
}

static int close_file(void* file) { return fclose((FILE*)file); }

// Decodes the whole stream into one buffer that already carries the WAV
// header. Takes ownership of `file` in every case.
static int decode_to_wav(FILE* file, double volume, uint8_t** out_wav,
                         size_t* out_wav_bytes) {
  OggVorbis_File vf;
  // Read and close only: the stream is decoded once from start to end, so no
  // seek and no tell callback is given. ov_open_callbacks, not ov_open: the
  // upstream documentation requires it on Windows
  // (https://xiph.org/vorbis/doc/vorbisfile/ov_open.html).
  const ov_callbacks callbacks = {read_from_file, NULL, close_file, NULL};
  if (ov_open_callbacks(file, &vf, NULL, 0, callbacks) != 0) {
    fclose(file);
    return kExitDecode;
  }
  // From here ov_clear closes the file.

  const vorbis_info* info = ov_info(&vf, -1);
  if (info == NULL || (info->channels != 1 && info->channels != 2) ||
      info->rate < 8000 || info->rate > 192000) {
    ov_clear(&vf);
    return kExitFormat;
  }
  const uint32_t channels = (uint32_t)info->channels;
  const uint32_t rate = (uint32_t)info->rate;

  size_t capacity = (size_t)256 * 1024;
  size_t used = CLEONA_PLAY_WAV_HEADER_BYTES;
  uint8_t* wav = (uint8_t*)malloc(capacity);
  if (wav == NULL) {
    ov_clear(&vf);
    return kExitMemory;
  }

  int first_section = -1;
  for (;;) {
    if (capacity - used < 4096) {
      if (capacity - CLEONA_PLAY_WAV_HEADER_BYTES >= CLEONA_PLAY_MAX_PCM_BYTES) {
        free(wav);
        ov_clear(&vf);
        return kExitFormat;
      }
      const size_t grown = capacity * 2;
      uint8_t* bigger = (uint8_t*)realloc(wav, grown);
      if (bigger == NULL) {
        free(wav);
        ov_clear(&vf);
        return kExitMemory;
      }
      wav = bigger;
      capacity = grown;
    }
    int section = 0;
    // 16-bit signed little-endian, the format of a PCM WAV.
    const long got = ov_read(&vf, (char*)(wav + used), 4096, 0, 2, 1, &section);
    if (got == 0) break;
    if (got < 0) {
      free(wav);
      ov_clear(&vf);
      return kExitDecode;
    }
    // A chained stream may change channel count and rate from one section to
    // the next; one WAV header cannot describe that. Only the first section
    // is played.
    if (first_section < 0) first_section = section;
    if (section != first_section) break;
    used += (size_t)got;
  }
  ov_clear(&vf);

  const size_t pcm_bytes = used - CLEONA_PLAY_WAV_HEADER_BYTES;
  if (pcm_bytes == 0) {
    free(wav);
    return kExitDecode;
  }
  apply_volume(wav + CLEONA_PLAY_WAV_HEADER_BYTES, pcm_bytes, volume);
  write_wav_header(wav, (uint32_t)pcm_bytes, channels, rate);
  *out_wav = wav;
  *out_wav_bytes = used;
  return kExitOk;
}

static int parse_volume(const char* text, double* out) {
  char* end = NULL;
  const double v = strtod(text, &end);
  if (end == text || *end != '\0') return 0;
  *out = v < 0.0 ? 0.0 : (v > 1.0 ? 1.0 : v);
  return 1;
}

#ifdef _WIN32

// Windows subsystem, no window: a console program started from the daemon
// would flash a console window on every sound.
int WINAPI WinMain(HINSTANCE instance, HINSTANCE previous, LPSTR command_line,
                   int show) {
  (void)instance;
  (void)previous;
  (void)command_line;
  (void)show;

  int argc = 0;
  LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  if (argv == NULL) return kExitUsage;

  const wchar_t* path = NULL;
  double volume = 1.0;
  int check_only = 0;
  for (int i = 1; i < argc; i++) {
    if (wcscmp(argv[i], L"--check") == 0) {
      check_only = 1;
    } else if (wcscmp(argv[i], L"--volume") == 0 && i + 1 < argc) {
      char narrow[64];
      const int n = WideCharToMultiByte(CP_UTF8, 0, argv[++i], -1, narrow,
                                        (int)sizeof(narrow), NULL, NULL);
      if (n <= 0 || !parse_volume(narrow, &volume)) {
        LocalFree(argv);
        return kExitUsage;
      }
    } else if (path == NULL) {
      path = argv[i];
    } else {
      LocalFree(argv);
      return kExitUsage;
    }
  }
  if (path == NULL) {
    LocalFree(argv);
    return kExitUsage;
  }

  FILE* file = _wfopen(path, L"rb");
  LocalFree(argv);
  if (file == NULL) return kExitOpen;

  uint8_t* wav = NULL;
  size_t wav_bytes = 0;
  const int decoded = decode_to_wav(file, volume, &wav, &wav_bytes);
  if (decoded != kExitOk) return decoded;
  if (check_only) {
    free(wav);
    return kExitOk;
  }

  // SND_SYNC: return when the sound has ended, so the exit of this process is
  // the end of the sound. SND_NODEFAULT: stay silent instead of playing the
  // system default sound when ours cannot be played.
  const BOOL played =
      PlaySoundW((LPCWSTR)wav, NULL, SND_MEMORY | SND_SYNC | SND_NODEFAULT);
  free(wav);
  return played ? kExitOk : kExitDevice;
}

#else

// Other platforms have their own players (v4_2 §22.6, §27.7). This entry
// exists so that the decode path can be built and checked where the project
// is developed; it never opens a device.
int main(int argc, char** argv) {
  const char* path = NULL;
  double volume = 1.0;
  int check_only = 0;
  for (int i = 1; i < argc; i++) {
    if (strcmp(argv[i], "--check") == 0) {
      check_only = 1;
    } else if (strcmp(argv[i], "--volume") == 0 && i + 1 < argc) {
      if (!parse_volume(argv[++i], &volume)) return kExitUsage;
    } else if (path == NULL) {
      path = argv[i];
    } else {
      return kExitUsage;
    }
  }
  if (path == NULL || !check_only) return kExitUsage;

  FILE* file = fopen(path, "rb");
  if (file == NULL) return kExitOpen;
  uint8_t* wav = NULL;
  size_t wav_bytes = 0;
  const int decoded = decode_to_wav(file, volume, &wav, &wav_bytes);
  if (decoded != kExitOk) return decoded;
  // Machine-readable result for the check script: bytes, channels, rate.
  printf("%zu %u %u\n", wav_bytes - CLEONA_PLAY_WAV_HEADER_BYTES,
         (unsigned)(wav[22] | (wav[23] << 8)),
         (unsigned)(wav[24] | (wav[25] << 8) | (wav[26] << 16) |
                    ((unsigned)wav[27] << 24)));
  free(wav);
  return kExitOk;
}

#endif
