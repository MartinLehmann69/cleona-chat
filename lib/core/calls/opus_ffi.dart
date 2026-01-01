/// FFI bindings for libopus (audio codec).
///
/// Opus is the standard codec for VoIP (RFC 6716).
/// Reduces audio bandwidth from 256 kbps (raw PCM) to ~24-32 kbps.
///
/// Configuration (V1.9):
/// - Sample rate and frame size come from the caller (VoiceSession.format)
///   to respect invariant I3 ("no assumed sample rate").
/// - Mono, 20 ms frame duration.
/// - DTX enabled, Inband-FEC enabled, bitrate 28 kbps.
/// - **CBR since 2026-09-06 (owner's decision, variant C).** The bitrate is
///   a *ceiling*, not a target: every packet is exactly
///   [opusCbrFrameBytes] = 70 B. See [OpusFFI._configureEncoder] for the
///   measurement that forced this and for what it costs.
///
/// S368: the parameterless `OpusFFI()` and the two constants
/// `opusSampleRate` / `opusFrameSamples` have fallen. They all carried
/// the same rationale ("for backward compatibility") and had
/// zero users in `lib/`/`bin/`. [OpusFFI.withFormat] is the only way —
/// the format comes from the platform, never from a constant.
library;

import 'dart:ffi';
import 'dart:io';
import 'package:cleona/core/platform/app_paths.dart';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

// ── Opus Constants ──────────────────────────────────────────────────────

/// Opus Application Type: Optimized for speech (VoIP).
const int opusApplicationVoip = 2048;

/// Opus OK Return Code.
const int opusOk = 0;

/// Maximum packet size for an Opus frame.
const int opusMaxPacketSize = 4000;

// S368: here stood `opusSampleRate = 16000` and
// `opusFrameSamples = 320`, both with the addition "Legacy … for backward
// compatibility. New code must NOT use this". Their only user was the
// parameterless constructor, which falls with them; outside this file
// there was not a single one in `lib/` and `bin/`. A constant that nobody
// may use and nobody uses is an invitation to do it anyway.

/// Mono.
const int opusChannels = 1;

// ── Opus CTL Constants ──────────────────────────────────────────────────

/// `OPUS_SET_BITRATE` — sets the encoder bitrate in bits/second.
const int _opusSetBitrate = 4002;

/// `OPUS_SET_INBAND_FEC` — enables (1) or disables (0) inband FEC.
const int _opusSetInbandFec = 4012;

/// `OPUS_SET_PACKET_LOSS_PERC` — expected packet loss percentage (0-100).
const int _opusSetPacketLossPerc = 4014;

/// `OPUS_SET_DTX` — enables (1) or disables (0) discontinuous transmission.
const int _opusSetDtx = 4016;

/// `OPUS_SET_VBR` — 1 selects variable, 0 selects constant bitrate.
///
/// Not to be confused with `OPUS_SET_VBR_CONSTRAINT` (4020). That one is
/// **already 1 out of the factory** — measured on 2026-09-06 against
/// libopus.so.0.9.0 with `OPUS_GET_VBR_CONSTRAINT` on a fresh
/// `opus_encoder_create(rate, 1, OPUS_APPLICATION_VOIP)`, at 48 kHz and at
/// 16 kHz — so setting it changes nothing. Only this one does.
const int _opusSetVbr = 4006;

/// Bitrate (bits/second). 28000 is the midpoint of the spec range
/// (24-32 kbps).
///
/// Under CBR (see [OpusFFI._configureEncoder]) this is not a target but the
/// exact rate — the encoder emits [opusCbrFrameBytes] every frame.
const int _opusTargetBitrate = 28000;

/// Frames per second at the 20 ms frame duration [OpusFFI.withFormat]
/// enforces for every sample rate.
const int _opusFramesPerSecond = 50;

/// **The size of every Opus packet this class produces: 70 B.**
///
/// 28,000 bit/s ÷ 50 frames/s ÷ 8 = 70 B. Derived, not written down, so it
/// follows [_opusTargetBitrate] if that ever moves.
///
/// This is a **bound**, not a percentile: under CBR libopus emits exactly
/// this many bytes for every frame it is given. Measured 2026-09-06 over
/// 4,000 frames of four signal shapes at 48 kHz and 16 kHz (min = max = 70)
/// and over 500 adversarial frames at each of the five rates
/// `OpusFFI.withFormat` admits — 8/12/16/24/48 kHz — where the set of
/// observed packet lengths had exactly one element at every rate.
///
/// `DFrameClass.voice` carries 133 B. A 1:1 voice body is the Opus packet
/// itself (70 B, 63 B spare); a group body is `index(1) ‖ seq(4) ‖
/// nonce(12) ‖ AES-GCM(Opus)+tag(16)` = Opus + 33 B (103 B, 30 B spare).
/// Both fit with room, and now they fit *by construction*.
const int opusCbrFrameBytes =
    _opusTargetBitrate ~/ _opusFramesPerSecond ~/ 8;

/// Expected packet loss percentage for FEC tuning. 10% is typical for
/// VoIP over UDP with relay hops.
const int _opusExpectedLossPerc = 10;

// ── Native Function Types ────────────────────────────────────────────────

// OpusEncoder* opus_encoder_create(int Fs, int channels, int application, int *error)
typedef _OpusEncoderCreateNative = Pointer<Void> Function(
    Int32, Int32, Int32, Pointer<Int32>);
typedef _OpusEncoderCreateDart = Pointer<Void> Function(
    int, int, int, Pointer<Int32>);

// void opus_encoder_destroy(OpusEncoder *st)
typedef _OpusEncoderDestroyNative = Void Function(Pointer<Void>);
typedef _OpusEncoderDestroyDart = void Function(Pointer<Void>);

// int opus_encode(OpusEncoder*, const opus_int16*, int frame_size, unsigned char*, int max_data_bytes)
typedef _OpusEncodeNative = Int32 Function(
    Pointer<Void>, Pointer<Int16>, Int32, Pointer<Uint8>, Int32);
typedef _OpusEncodeDart = int Function(
    Pointer<Void>, Pointer<Int16>, int, Pointer<Uint8>, int);

// OpusDecoder* opus_decoder_create(int Fs, int channels, int *error)
typedef _OpusDecoderCreateNative = Pointer<Void> Function(
    Int32, Int32, Pointer<Int32>);
typedef _OpusDecoderCreateDart = Pointer<Void> Function(
    int, int, Pointer<Int32>);

// void opus_decoder_destroy(OpusDecoder *st)
typedef _OpusDecoderDestroyNative = Void Function(Pointer<Void>);
typedef _OpusDecoderDestroyDart = void Function(Pointer<Void>);

// int opus_decode(OpusDecoder*, const unsigned char*, int len, opus_int16*, int frame_size, int decode_fec)
typedef _OpusDecodeNative = Int32 Function(
    Pointer<Void>, Pointer<Uint8>, Int32, Pointer<Int16>, Int32, Int32);
typedef _OpusDecodeDart = int Function(
    Pointer<Void>, Pointer<Uint8>, int, Pointer<Int16>, int, int);

// int opus_encoder_ctl(OpusEncoder *st, int request, int value)
// Dart FFI has no varargs — we use the 3-arg (encoder, request, int) form
// and look it up under the same symbol name.
typedef _OpusEncoderCtlIntNative = Int32 Function(
    Pointer<Void>, Int32, Int32);
typedef _OpusEncoderCtlIntDart = int Function(Pointer<Void>, int, int);

// ── OpusFFI Class ────────────────────────────────────────────────────────

/// FFI wrapper for the libopus audio codec.
///
/// Usage (new — device rate from VoiceSession.format):
/// ```dart
/// final opus = OpusFFI.withFormat(
///   sampleRate: format.sampleRate,
///   frameSamples: format.frameSamples,
/// );
/// final encoded = opus.encode(pcm16Data);  // PCM -> Opus
/// final decoded = opus.decode(encoded);     // Opus -> PCM
/// opus.dispose();
/// ```
///
/// Legacy usage (hardcoded 16 kHz / 320 samples):
/// ```dart
/// final opus = OpusFFI();
/// ```
class OpusFFI {
  DynamicLibrary? _lib;
  Pointer<Void>? _encoder;
  Pointer<Void>? _decoder;
  bool _disposed = false;

  /// The sample rate this codec instance was created with.
  final int sampleRate;

  /// The number of samples per 20 ms frame at [sampleRate].
  final int frameSamples;

  // Lazy-initialized function pointers
  _OpusEncoderCreateDart? _encoderCreate;
  _OpusEncoderDestroyDart? _encoderDestroy;
  _OpusEncodeDart? _encode;
  _OpusDecoderCreateDart? _decoderCreate;
  _OpusDecoderDestroyDart? _decoderDestroy;
  _OpusDecodeDart? _decode;
  _OpusEncoderCtlIntDart? _encoderCtl;

  // S368: here stood the parameterless `OpusFFI()` with hard-wired
  // 16 kHz / 320 samples — "Exists for backward compatibility with
  // existing callers". Measured: **zero** callers in `lib/` and `bin/`,
  // only two in `test/`; both have been switched to `OpusFFI.withFormat`.
  // The fixed rate was moreover exactly what §10.4 forbids: the
  // format comes from the platform (`VoiceSession.format`), never from a
  // constant (I3, I4).

  /// Creates an Opus encoder/decoder pair at the given [sampleRate] and
  /// [frameSamples].
  ///
  /// Both values must come from the platform (VoiceSession.format), never
  /// from a constant (I3, I4). The encoder is configured with DTX, FEC and
  /// a 28 kbps target bitrate per spec V1.9.
  ///
  /// Throws [OpusNotAvailableException] if libopus is not found.
  /// Throws [ArgumentError] if [sampleRate] is not an Opus-supported rate
  /// or [frameSamples] does not match 20 ms at [sampleRate].
  OpusFFI.withFormat({
    required this.sampleRate,
    required this.frameSamples,
  }) {
    // Opus supports exactly these rates.
    const supportedRates = {8000, 12000, 16000, 24000, 48000};
    if (!supportedRates.contains(sampleRate)) {
      throw ArgumentError.value(
        sampleRate,
        'sampleRate',
        'Opus supports only $supportedRates',
      );
    }
    final expected = sampleRate * 20 ~/ 1000;
    if (frameSamples != expected) {
      throw ArgumentError.value(
        frameSamples,
        'frameSamples',
        'must be sampleRate * 20 / 1000 = $expected for $sampleRate Hz',
      );
    }

    _loadLibrary();
    _createEncoder();
    _configureEncoder();
    _createDecoder();
  }

  void _loadLibrary() {
    if (Platform.isIOS) {
      _lib = DynamicLibrary.process();
    } else {
      final libNames = _libSearchPaths();
      for (final name in libNames) {
        try {
          _lib = DynamicLibrary.open(name);
          break;
        } catch (_) {
          continue;
        }
      }
    }

    if (_lib == null) {
      throw OpusNotAvailableException(
          'libopus not found. Install hint — Linux: apt install libopus0. '
          'macOS: brew install opus, or drop libopus.dylib into '
          'Cleona.app/Contents/Frameworks/. Windows: libopus.dll beside cleona.exe.');
    }

    _encoderCreate = _lib!.lookupFunction<_OpusEncoderCreateNative,
        _OpusEncoderCreateDart>('opus_encoder_create');
    _encoderDestroy = _lib!.lookupFunction<_OpusEncoderDestroyNative,
        _OpusEncoderDestroyDart>('opus_encoder_destroy');
    _encode = _lib!
        .lookupFunction<_OpusEncodeNative, _OpusEncodeDart>('opus_encode');
    _decoderCreate = _lib!.lookupFunction<_OpusDecoderCreateNative,
        _OpusDecoderCreateDart>('opus_decoder_create');
    _decoderDestroy = _lib!.lookupFunction<_OpusDecoderDestroyNative,
        _OpusDecoderDestroyDart>('opus_decoder_destroy');
    _decode = _lib!
        .lookupFunction<_OpusDecodeNative, _OpusDecodeDart>('opus_decode');
    _encoderCtl = _lib!
        .lookupFunction<_OpusEncoderCtlIntNative, _OpusEncoderCtlIntDart>(
            'opus_encoder_ctl');
  }

  /// Bundle paths since S367 — rationale in `sodium_ffi.dart`
  /// (`_openLibsodium`): the daemon lies in `<bundleDir>/bin/`, its
  /// own directory no longer carries the libraries.
  ///
  /// Under Linux the bundle carries `libopus.so` itself (built by
  /// `linux/CMakeLists.txt`, installed to `bundle/lib/`) — there
  /// the bundle path is thus not an addition but the normal case.
  static List<String> _libSearchPaths() {
    if (Platform.isMacOS) {
      return [
        'libopus.dylib',
        'libopus.0.dylib',
        '${AppPaths.macFrameworksDir}/libopus.dylib',
        '@executable_path/../Frameworks/libopus.dylib',
        '/opt/homebrew/lib/libopus.dylib',
        '/opt/homebrew/lib/libopus.0.dylib',
        '/usr/local/lib/libopus.dylib',
        '/usr/local/lib/libopus.0.dylib',
      ];
    }
    if (Platform.isWindows) {
      return [
        'libopus.dll',
        'opus.dll',
        '${AppPaths.bundleDir}\\libopus.dll',
        '${AppPaths.bundleDir}\\opus.dll',
      ];
    }
    return [
      'libopus.so.0',
      'libopus.so',
      '${AppPaths.bundleLibDir}/libopus.so',
      '/usr/lib/libopus.so.0',
      '/usr/local/lib/libopus.so.0',
    ];
  }

  void _createEncoder() {
    final err = calloc<Int32>();
    try {
      _encoder = _encoderCreate!(
          sampleRate, opusChannels, opusApplicationVoip, err);
      if (err.value != opusOk || _encoder == null || _encoder == nullptr) {
        throw OpusNotAvailableException(
            'Failed to create Opus encoder: error=${err.value}');
      }
    } finally {
      calloc.free(err);
    }
  }

  /// Configures encoder with CBR, DTX, FEC, bitrate and packet loss
  /// percentage.
  ///
  /// Called only from [OpusFFI.withFormat] — the legacy constructor does not
  /// configure these so that smoke_calls.dart keeps passing unchanged.
  ///
  /// ## Why CBR (owner's decision 2026-09-06, variant C)
  ///
  /// `DFrameClass.voice` is a **fixed** 176 B size class: a body that does
  /// not fit is refused at the sender, never promoted to the next class,
  /// because a size difference on the wire is the fingerprint the classes
  /// exist to remove. So the class only holds if the codec has an upper
  /// bound per frame. Until today it had none, and the class size was twice
  /// derived from a statistic that was mistaken for one:
  ///
  /// * "60-80 B" produced the 128 B class. That range is the codec's
  ///   **mean**, and 100 % of group frames overflowed the class.
  /// * "95 B" produced the 176 B class. That is the **maximum of one
  ///   sample**, and 0.3-0.9 % of group frames still overflowed.
  ///
  /// Both times the fix bought a probability, not a promise. The reason is
  /// [_opusSetBitrate]: it sets a *target*. A VBR frame may exceed it, and
  /// the only hard ceiling in the encoder is [opusMaxPacketSize] = 4000 B.
  ///
  /// **`OPUS_SET_VBR_CONSTRAINT(1)` does not help, and this is measured,
  /// not read.** It is already 1 out of the factory (verified with
  /// `OPUS_GET_VBR_CONSTRAINT` on a fresh encoder at 48 kHz and 16 kHz).
  /// Setting it explicitly and re-running the whole population produced a
  /// frame-length sequence identical to the unset run in **4,000 of 4,000
  /// frames** at both rates — same p50, same maximum of 110 B. Constrained
  /// VBR bounds a short-window *average*, not a frame.
  ///
  /// [_opusSetVbr] `= 0` does help, and it is the only setting that does:
  /// every packet then measures exactly [opusCbrFrameBytes] = 70 B.
  /// 70 + 33 B of group overhead = 103 B against the 133 B the class
  /// carries. **The residual is not small any more, it is structurally
  /// zero** — the encoder cannot produce a frame that overflows.
  ///
  /// ## What it costs, measured on the same four signal shapes
  ///
  /// Band-energy log-spectral distance against the input, 20 log-spaced
  /// bands, bands more than 40 dB below the frame's strongest band
  /// excluded, run offset determined per shape and mode by
  /// cross-correlation (lower is better, dB):
  ///
  /// | shape | 48 kHz VBR → CBR | 16 kHz VBR → CBR |
  /// |---|---|---|
  /// | speech-like | 3.4 → 7.5 | 6.0 → 10.5 |
  /// | white noise | 43.1 → 46.6 | 3.9 → 6.8 |
  /// | sweep | 47.4 → 59.6 | 0.6 → 2.0 |
  /// | DTX bursts | 0.3 → 1.8 | 0.2 → 0.5 |
  ///
  /// The price lands where the VBR peaks were: transients and sweeps, i.e.
  /// exactly the frames CBR is no longer allowed to spend extra bits on.
  /// **None of this is a listening test, and synthetic tones are not
  /// speech** — what is established is the direction and rough size of the
  /// loss, not its perceptual weight.
  ///
  /// ## What it does NOT cost
  ///
  /// Nothing on the wire. A D-frame is padded to its class either way, so
  /// the 61.5 → 70.0 B mean packet is invisible outside the AEAD; the wire
  /// stays at 176 B × 50 = 8.8 kB/s per direction. DTX keeps its CTL but
  /// stops shrinking pauses (measured minimum rises from 8-9 B to 70 B),
  /// which likewise costs no wire bytes for the same reason — every
  /// captured frame is sent regardless (`audio_mixer.dart`, no silence
  /// suppression) and padded regardless.
  void _configureEncoder() {
    void ctl(int request, int value, String name) {
      final rc = _encoderCtl!(_encoder!, request, value);
      if (rc != opusOk) {
        throw OpusCodecException(
            'opus_encoder_ctl($name=$value) failed: $rc');
      }
    }

    ctl(_opusSetBitrate, _opusTargetBitrate, 'OPUS_SET_BITRATE');
    // Must come after the bitrate: CBR pins the frame to whatever rate is
    // set at encode time, so the order is what makes 70 B the number.
    ctl(_opusSetVbr, 0, 'OPUS_SET_VBR');
    ctl(_opusSetDtx, 1, 'OPUS_SET_DTX');
    ctl(_opusSetInbandFec, 1, 'OPUS_SET_INBAND_FEC');
    ctl(_opusSetPacketLossPerc, _opusExpectedLossPerc,
        'OPUS_SET_PACKET_LOSS_PERC');
  }

  void _createDecoder() {
    final err = calloc<Int32>();
    try {
      _decoder = _decoderCreate!(sampleRate, opusChannels, err);
      if (err.value != opusOk || _decoder == null || _decoder == nullptr) {
        throw OpusNotAvailableException(
            'Failed to create Opus decoder: error=${err.value}');
      }
    } finally {
      calloc.free(err);
    }
  }

  /// Compress PCM-16 audio to Opus.
  ///
  /// [pcm16]: Int16 PCM data (mono, [frameSamples] samples = [frameSamples]*2
  /// bytes).
  /// Returns compressed Opus packet.
  Uint8List encode(Uint8List pcm16) {
    if (_disposed || _encoder == null) {
      throw OpusNotAvailableException('Encoder disposed');
    }

    final numSamples = pcm16.length ~/ 2; // 16-bit = 2 bytes per sample
    final inputPtr = calloc<Int16>(numSamples);
    final outputPtr = calloc<Uint8>(opusMaxPacketSize);

    try {
      // Copy PCM data into native memory.
      final view = ByteData.view(pcm16.buffer, pcm16.offsetInBytes);
      for (var i = 0; i < numSamples; i++) {
        inputPtr[i] = view.getInt16(i * 2, Endian.little);
      }

      final encodedBytes = _encode!(
        _encoder!,
        inputPtr,
        numSamples,
        outputPtr,
        opusMaxPacketSize,
      );

      if (encodedBytes < 0) {
        throw OpusCodecException('Opus encode failed: $encodedBytes');
      }

      return Uint8List.fromList(outputPtr.asTypedList(encodedBytes));
    } finally {
      calloc.free(inputPtr);
      calloc.free(outputPtr);
    }
  }

  /// Decompress Opus packet to PCM-16 audio.
  ///
  /// [opusData]: Compressed Opus packet.
  /// [decodeFec]: if true, decode the FEC data from this packet to recover
  /// the *previous* frame. Call with the **next** received packet after a
  /// gap to recover the lost frame.
  /// Returns PCM-16 data (mono, [frameSamples]*2 bytes).
  Uint8List decode(Uint8List opusData, {bool decodeFec = false}) {
    if (_disposed || _decoder == null) {
      throw OpusNotAvailableException('Decoder disposed');
    }

    final inputPtr = calloc<Uint8>(opusData.length);
    final outputPtr = calloc<Int16>(frameSamples);

    try {
      inputPtr.asTypedList(opusData.length).setAll(0, opusData);

      final decodedSamples = _decode!(
        _decoder!,
        inputPtr,
        opusData.length,
        outputPtr,
        frameSamples,
        decodeFec ? 1 : 0,
      );

      if (decodedSamples < 0) {
        throw OpusCodecException('Opus decode failed: $decodedSamples');
      }

      // Int16 -> Uint8 (Little-Endian)
      final result = Uint8List(decodedSamples * 2);
      final view = ByteData.view(result.buffer);
      for (var i = 0; i < decodedSamples; i++) {
        view.setInt16(i * 2, outputPtr[i], Endian.little);
      }
      return result;
    } finally {
      calloc.free(inputPtr);
      calloc.free(outputPtr);
    }
  }

  /// Packet Loss Concealment: replace missing frame with interpolation.
  Uint8List decodePlc() {
    if (_disposed || _decoder == null) {
      throw OpusNotAvailableException('Decoder disposed');
    }

    final outputPtr = calloc<Int16>(frameSamples);
    try {
      final decodedSamples = _decode!(
        _decoder!,
        nullptr.cast<Uint8>(),
        0, // len = 0 -> PLC
        outputPtr,
        frameSamples,
        0,
      );

      if (decodedSamples < 0) {
        throw OpusCodecException('Opus PLC failed: $decodedSamples');
      }

      final result = Uint8List(decodedSamples * 2);
      final view = ByteData.view(result.buffer);
      for (var i = 0; i < decodedSamples; i++) {
        view.setInt16(i * 2, outputPtr[i], Endian.little);
      }
      return result;
    } finally {
      calloc.free(outputPtr);
    }
  }

  /// Whether this codec instance has been disposed.
  bool get isDisposed => _disposed;

  /// Release resources.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_encoder != null && _encoder != nullptr) {
      _encoderDestroy!(_encoder!);
      _encoder = null;
    }
    if (_decoder != null && _decoder != nullptr) {
      _decoderDestroy!(_decoder!);
      _decoder = null;
    }
  }

  /// Whether libopus is available on the system.
  ///
  /// Queries the same list that [_loadLibrary] uses (S367). Before,
  /// this function only tried `libopus.so.0` and `libopus.so` — it
  /// would always have reported `false` on Windows and macOS and on Linux
  /// overlooked the shipped `bundle/lib/libopus.so`. Two
  /// procedures for the same question are a source of error without
  /// benefit.
  static bool isAvailable() {
    for (final name in _libSearchPaths()) {
      try {
        DynamicLibrary.open(name);
        return true;
      } catch (_) {
        continue;
      }
    }
    return false;
  }
}

/// libopus not available.
class OpusNotAvailableException implements Exception {
  final String message;
  OpusNotAvailableException(this.message);

  @override
  String toString() => 'OpusNotAvailableException: $message';
}

/// Opus codec error.
class OpusCodecException implements Exception {
  final String message;
  OpusCodecException(this.message);

  @override
  String toString() => 'OpusCodecException: $message';
}
