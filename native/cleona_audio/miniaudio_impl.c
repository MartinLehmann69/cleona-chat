// miniaudio implementation trigger — single-translation-unit pattern.
// miniaudio.h is the entire library; this .c file emits the implementations.
//
// Vendored: miniaudio v0.11.21 (2023-11-15)
// SHA256:   6b2029714f8634c4d7c70cc042f45074e0565766113fc064f20cd27c986be9c9
// License:  Public Domain / MIT-0 (chosen at compile-time via MA_NO_*)
//
// Backend-Konfiguration:
//   Linux:        PulseAudio + ALSA  (PA preferred, ALSA fallback)
//   Android:      AAudio + OpenSL ES (AAudio for API 26+, OpenSL fallback)
//   Windows:      WASAPI             (Communications mode for low-latency voice)
//   macOS / iOS:  Core Audio         (Folge-PRs)
#define MINIAUDIO_IMPLEMENTATION

#define MA_NO_JACK
#define MA_NO_SNDIO
#define MA_NO_AUDIO4
#define MA_NO_DSOUND
#define MA_NO_WINMM
#define MA_NO_NULL  // disable null backend in production

#include "miniaudio.h"
