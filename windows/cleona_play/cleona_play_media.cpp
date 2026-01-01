// cleona-play --media: plays ONE voice message (or any audio the system can
// decode) from a URL and exits -- the Windows counterpart of `ffplay`/`ffprobe`
// in the desktop branch of the chat's audio player
// (lib/ui/screens/chat_screen.dart `_AudioPlayerWidgetState`).
//
// Why this exists: a voice message is AAC-LC in an MPEG-4 container
// (`record`, `AudioEncoder.aacLc`, v4_2 §27.6). Windows ships no `ffplay`, and
// v4_2 §27.7 allows Windows no external programs besides the bundled helpers
// (`cleona-play.exe`, `cleona-notify.exe`). The AAC decoder of Windows itself
// (Media Foundation) reads it -- no decoder of our own, nothing to bundle.
//
// The attachment is encrypted at rest; the GUI hands a loopback URL of
// `MediaVault` (http://127.0.0.1:<port>/..., Range requests answered), so the
// plain text never reaches the disk -- the same URL `ffplay` reads on Linux.
//
// Output: waveOut, fed sample by sample while decoding -- memory stays bounded
// whatever the length of the message. Ending the process ends the sound (the
// GUI kills it on pause, like `ffplay`).
//
// Media Foundation documentation:
//   Source Reader      https://learn.microsoft.com/windows/win32/medfound/source-reader
//   MF_PD_DURATION     https://learn.microsoft.com/windows/win32/medfound/mf-pd-duration-attribute
//   SetCurrentPosition https://learn.microsoft.com/windows/win32/api/mfreadwrite/nf-mfreadwrite-imfsourcereader-setcurrentposition
//   waveOutWrite       https://learn.microsoft.com/windows/win32/api/mmeapi/nf-mmeapi-waveoutwrite

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <mmsystem.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <propvarutil.h>

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "cleona_play_media.h"

namespace {

// Exit codes shared with cleona_play.c.
constexpr int kExitOk = 0;
constexpr int kExitOpen = 3;
constexpr int kExitDecode = 4;
constexpr int kExitDevice = 5;
constexpr int kExitFormat = 6;
constexpr int kExitMemory = 7;
constexpr int kExitPlatform = 8;

// Queued output buffers. Each holds one decoded sample (AAC: 1024 frames,
// about 21-23 ms); eight keep ~170 ms in flight.
constexpr int kBuffers = 8;

template <typename T>
void release(T** p) {
  if (*p != nullptr) {
    (*p)->Release();
    *p = nullptr;
  }
}

// One COM + Media Foundation session for the life of the process.
struct MfSession {
  bool com = false;
  bool mf = false;
  ~MfSession() {
    if (mf) MFShutdown();
    if (com) CoUninitialize();
  }
  bool start() {
    com = SUCCEEDED(CoInitializeEx(nullptr, COINIT_MULTITHREADED));
    if (!com) return false;
    mf = SUCCEEDED(MFStartup(MF_VERSION, MFSTARTUP_LITE));
    return mf;
  }
};

// Opens [url] and sets the first audio stream to 16-bit PCM output.
int open_reader(const wchar_t* url, IMFSourceReader** out) {
  IMFSourceReader* reader = nullptr;
  if (FAILED(MFCreateSourceReaderFromURL(url, nullptr, &reader))) {
    return kExitOpen;
  }
  const DWORD audio = static_cast<DWORD>(MF_SOURCE_READER_FIRST_AUDIO_STREAM);
  reader->SetStreamSelection(static_cast<DWORD>(MF_SOURCE_READER_ALL_STREAMS),
                             FALSE);
  if (FAILED(reader->SetStreamSelection(audio, TRUE))) {
    release(&reader);
    return kExitFormat;
  }
  IMFMediaType* pcm = nullptr;
  if (FAILED(MFCreateMediaType(&pcm))) {
    release(&reader);
    return kExitMemory;
  }
  pcm->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
  pcm->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM);
  pcm->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
  const HRESULT set = reader->SetCurrentMediaType(audio, nullptr, pcm);
  release(&pcm);
  if (FAILED(set)) {
    release(&reader);
    return kExitFormat;
  }
  *out = reader;
  return kExitOk;
}

// Duration of the presentation in milliseconds, or -1.
int64_t duration_ms(IMFSourceReader* reader) {
  PROPVARIANT var;
  PropVariantInit(&var);
  int64_t ms = -1;
  if (SUCCEEDED(reader->GetPresentationAttribute(
          static_cast<DWORD>(MF_SOURCE_READER_MEDIASOURCE), MF_PD_DURATION,
          &var)) &&
      var.vt == VT_UI8) {
    ms = static_cast<int64_t>(var.uhVal.QuadPart / 10000);  // 100 ns units
  }
  PropVariantClear(&var);
  return ms;
}

void write_stdout(const char* text) {
  const HANDLE out = GetStdHandle(STD_OUTPUT_HANDLE);
  if (out == nullptr || out == INVALID_HANDLE_VALUE) return;
  DWORD written = 0;
  WriteFile(out, text, static_cast<DWORD>(strlen(text)), &written, nullptr);
}

void apply_volume(uint8_t* pcm, DWORD bytes, double volume) {
  if (volume >= 1.0) return;
  const int32_t gain = static_cast<int32_t>(volume * 65536.0 + 0.5);
  for (DWORD i = 0; i + 1 < bytes; i += 2) {
    const int16_t s = static_cast<int16_t>(
        static_cast<uint16_t>(pcm[i]) | (static_cast<uint16_t>(pcm[i + 1]) << 8));
    const int32_t scaled = (static_cast<int32_t>(s) * gain) / 65536;
    pcm[i] = static_cast<uint8_t>(scaled & 0xff);
    pcm[i + 1] = static_cast<uint8_t>((scaled >> 8) & 0xff);
  }
}

struct Output {
  HWAVEOUT device = nullptr;
  HANDLE done = nullptr;  // signalled by waveOut whenever a buffer finished
  WAVEHDR headers[kBuffers] = {};
  uint8_t* data[kBuffers] = {};
  DWORD capacity[kBuffers] = {};

  ~Output() {
    if (device != nullptr) {
      waveOutReset(device);
      for (int i = 0; i < kBuffers; i++) {
        if (headers[i].dwFlags & WHDR_PREPARED) {
          waveOutUnprepareHeader(device, &headers[i], sizeof(WAVEHDR));
        }
      }
      waveOutClose(device);
    }
    for (int i = 0; i < kBuffers; i++) HeapFree(GetProcessHeap(), 0, data[i]);
    if (done != nullptr) CloseHandle(done);
  }

  int open(IMFSourceReader* reader) {
    IMFMediaType* type = nullptr;
    if (FAILED(reader->GetCurrentMediaType(
            static_cast<DWORD>(MF_SOURCE_READER_FIRST_AUDIO_STREAM), &type))) {
      return kExitFormat;
    }
    UINT32 channels = 0;
    UINT32 rate = 0;
    type->GetUINT32(MF_MT_AUDIO_NUM_CHANNELS, &channels);
    type->GetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, &rate);
    release(&type);
    if (channels < 1 || channels > 2 || rate < 8000 || rate > 192000) {
      return kExitFormat;
    }
    WAVEFORMATEX format = {};
    format.wFormatTag = WAVE_FORMAT_PCM;
    format.nChannels = static_cast<WORD>(channels);
    format.nSamplesPerSec = rate;
    format.wBitsPerSample = 16;
    format.nBlockAlign = static_cast<WORD>(channels * 2);
    format.nAvgBytesPerSec = rate * format.nBlockAlign;
    done = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    if (done == nullptr) return kExitMemory;
    if (waveOutOpen(&device, WAVE_MAPPER, &format,
                    reinterpret_cast<DWORD_PTR>(done), 0,
                    CALLBACK_EVENT) != MMSYSERR_NOERROR) {
      device = nullptr;
      return kExitDevice;
    }
    return kExitOk;
  }

  // A buffer that is not queued, waiting for one if all are.
  int free_slot() {
    for (;;) {
      for (int i = 0; i < kBuffers; i++) {
        if (!(headers[i].dwFlags & WHDR_PREPARED) ||
            (headers[i].dwFlags & WHDR_DONE)) {
          return i;
        }
      }
      WaitForSingleObject(done, INFINITE);
    }
  }

  int queue(const uint8_t* pcm, DWORD bytes, double volume) {
    const int i = free_slot();
    WAVEHDR* h = &headers[i];
    if (h->dwFlags & WHDR_PREPARED) {
      waveOutUnprepareHeader(device, h, sizeof(WAVEHDR));
    }
    if (capacity[i] < bytes) {
      HeapFree(GetProcessHeap(), 0, data[i]);
      data[i] = static_cast<uint8_t*>(HeapAlloc(GetProcessHeap(), 0, bytes));
      capacity[i] = data[i] == nullptr ? 0 : bytes;
      if (data[i] == nullptr) return kExitMemory;
    }
    memcpy(data[i], pcm, bytes);
    apply_volume(data[i], bytes, volume);
    ZeroMemory(h, sizeof(WAVEHDR));
    h->lpData = reinterpret_cast<LPSTR>(data[i]);
    h->dwBufferLength = bytes;
    if (waveOutPrepareHeader(device, h, sizeof(WAVEHDR)) != MMSYSERR_NOERROR ||
        waveOutWrite(device, h, sizeof(WAVEHDR)) != MMSYSERR_NOERROR) {
      return kExitDevice;
    }
    return kExitOk;
  }

  // Returns when every queued buffer has been played.
  void drain() {
    for (;;) {
      bool busy = false;
      for (int i = 0; i < kBuffers; i++) {
        if ((headers[i].dwFlags & WHDR_PREPARED) &&
            !(headers[i].dwFlags & WHDR_DONE)) {
          busy = true;
        }
      }
      if (!busy) return;
      WaitForSingleObject(done, 200);
    }
  }
};

int play(IMFSourceReader* reader, int64_t start_ms, double volume) {
  if (start_ms > 0) {
    PROPVARIANT pos;
    InitPropVariantFromInt64(start_ms * 10000, &pos);  // 100 ns units
    reader->SetCurrentPosition(GUID_NULL, pos);
    PropVariantClear(&pos);
  }
  Output out;
  const int opened = out.open(reader);
  if (opened != kExitOk) return opened;

  bool any = false;
  for (;;) {
    DWORD flags = 0;
    IMFSample* sample = nullptr;
    if (FAILED(reader->ReadSample(
            static_cast<DWORD>(MF_SOURCE_READER_FIRST_AUDIO_STREAM), 0,
            nullptr, &flags, nullptr, &sample))) {
      return kExitDecode;
    }
    if (flags & MF_SOURCE_READERF_ENDOFSTREAM) {
      release(&sample);
      break;
    }
    // A format change in the middle of the stream cannot be followed by an
    // open waveOut device; what came so far is played.
    if (flags & MF_SOURCE_READERF_CURRENTMEDIATYPECHANGED) {
      release(&sample);
      break;
    }
    if (sample == nullptr) continue;
    IMFMediaBuffer* buffer = nullptr;
    if (FAILED(sample->ConvertToContiguousBuffer(&buffer))) {
      release(&sample);
      return kExitDecode;
    }
    BYTE* bytes = nullptr;
    DWORD length = 0;
    int queued = kExitOk;
    if (SUCCEEDED(buffer->Lock(&bytes, nullptr, &length))) {
      if (length > 0) {
        queued = out.queue(bytes, length, volume);
        any = true;
      }
      buffer->Unlock();
    }
    release(&buffer);
    release(&sample);
    if (queued != kExitOk) return queued;
  }
  out.drain();
  return any ? kExitOk : kExitDecode;
}

}  // namespace

extern "C" int cleona_play_media(const wchar_t* url, int probe_only,
                                 long long start_ms, double volume) {
  MfSession session;
  if (!session.start()) return kExitPlatform;
  IMFSourceReader* reader = nullptr;
  const int opened = open_reader(url, &reader);
  if (opened != kExitOk) return opened;
  int result = kExitOk;
  if (probe_only) {
    // Machine-readable: the duration in milliseconds and a newline.
    const int64_t ms = duration_ms(reader);
    if (ms < 0) {
      result = kExitDecode;
    } else {
      char line[32];
      _snprintf_s(line, sizeof(line), _TRUNCATE, "%lld\n",
                  static_cast<long long>(ms));
      write_stdout(line);
    }
  } else {
    result = play(reader, start_ms, volume);
  }
  release(&reader);
  return result;
}
