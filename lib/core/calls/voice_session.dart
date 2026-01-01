/// Dart FFI binding for `native/cleona_voice/cleona_voice.h` — the single
/// boundary between Cleona and the operating system's voice-communication
/// chain (architecture §10.4, SPEC §4 / work package V0.2).
///
/// There is exactly **one** binding for five native implementations. Anything
/// that is platform-specific lives behind the C ABI; anything that is policy
/// (route selection, mute semantics in the UI) lives above this file, once.
///
/// ## The invariants this file is responsible for
///
/// * **I3 — no assumed sample rate.** [VoiceSession.format] is whatever
///   `cleona_voice_open()` reported. There is no default rate anywhere in this
///   file, and `rateHint` is documented as a hint that may be ignored.
/// * **I4 — no assumed frame size.** Buffers are sized from the reported
///   `frame_bytes`, and every capture/playback call validates the caller's
///   buffer against it. A frame of the wrong size is rejected, never padded.
/// * **I5 — no timer in the playback path.** There is no `Timer`, no
///   `Stream.periodic` and no `Future.delayed` in this file. Pacing is the
///   output device's job; a Dart timer cannot hold 50 Hz under call-time UI
///   load (learned in S278, normative in §10.4).
/// * **I6 — mute never tears a stream down.** [micMuted] and [outputMuted] are
///   pure property writes; neither stops the session. Since erratum E6a the
///   backend also *reports* both states, so §10.4's "the mute states survive
///   route changes" is checkable instead of merely asserted. The values arrive
///   in `VoiceReport.rawWireValues` under `mic_muted` / `output_muted`; the
///   typed fields on `VoiceReport` are work package V1.7's, which owns
///   `voice_report.dart`.
/// * **I11 — the report is never guessed.** [getReport] converts what the
///   backend said and nothing more; see `voice_report.dart`.
///
/// ## Threading
///
/// [readCaptureFrameInto] blocks for up to its timeout, so the capture loop
/// belongs in its own isolate. Everything else returns promptly. [close] must
/// not race with a capture read — stop the loop first, then close.
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'package:cleona/core/calls/voice_report.dart';

export 'package:cleona/core/calls/voice_report.dart';

// ─────────────────────────────────────────────────────────────────────────
// ABI constants — mirrored from native/cleona_voice/cleona_voice.h.
// Keep the two in sync in the same commit; the C header carries a
// _Static_assert on the report layout for the same reason.
// ─────────────────────────────────────────────────────────────────────────

/// Return codes of the voice ABI. Every failure is negative — callers must
/// test `< 0`, never `== -1`.
abstract final class VoiceErr {
  static const int ok = 0;
  static const int invalidArg = -1;
  static const int closed = -2;
  static const int notStarted = -3;
  static const int alreadyStarted = -4;
  static const int frameSize = -5;

  /// The route constant is valid but not currently available — what a desktop
  /// backend returns for [VoiceRoute.earpiece]. SPEC §4 requires this instead
  /// of a silent no-op, so the UI can show a device chooser rather than a
  /// button that does nothing.
  static const int routeUnavailable = -6;
  static const int routeUnsupported = -7;
  static const int backend = -8;
  static const int noDevice = -9;
  static const int permission = -10;
  static const int unsupported = -11;

  static String describe(int code) {
    switch (code) {
      case ok:
        return 'ok';
      case invalidArg:
        return 'invalid argument';
      case closed:
        return 'session closed';
      case notStarted:
        return 'session not started';
      case alreadyStarted:
        return 'session already started';
      case frameSize:
        return 'wrong frame size';
      case routeUnavailable:
        return 'route not available on this device';
      case routeUnsupported:
        return 'backend has no route control';
      case backend:
        return 'platform API refused';
      case noDevice:
        return 'no usable audio device';
      case permission:
        return 'microphone permission denied';
      case unsupported:
        return 'not implemented by this backend';
      default:
        return 'unknown error $code';
    }
  }
}

/// Result of one [VoiceSession.readCaptureFrameInto].
enum VoiceCaptureStatus {
  /// Exactly `format.frameSamples` samples were written (I4).
  frame(1),

  /// Nothing was written; call again. Not an error.
  timeout(0),

  /// The session is stopped or closed — leave the capture loop.
  closed(-1);

  const VoiceCaptureStatus(this.wireValue);
  final int wireValue;

  static VoiceCaptureStatus fromWire(int v) {
    if (v == 1) return frame;
    if (v == 0) return timeout;
    return closed;
  }
}

/// Events delivered by polling (`CLEONA_VOICE_EV_*`).
///
/// Polling is deliberate: a callback would have to cross the FFI/isolate
/// boundary and would couple every platform backend to the Dart-side isolate
/// arrangement.
enum VoiceEvent {
  none(0),

  /// `arg` is the new `routes_available_mask`.
  routesChanged(1),

  /// Another call, Siri or the system took the audio session.
  interruptionBegin(2),
  interruptionEnd(3),

  /// `arg` is the new sample rate. The session re-reads the format and resizes
  /// its buffers before the next capture read (I3/I4).
  formatChanged(4),

  invalid(-1);

  const VoiceEvent(this.wireValue);
  final int wireValue;

  static VoiceEvent fromWire(int v) {
    for (final e in values) {
      if (e != invalid && e.wireValue == v) return e;
    }
    return invalid;
  }
}

/// One polled event.
class VoiceEventRecord {
  const VoiceEventRecord(this.event, this.arg);
  final VoiceEvent event;
  final int arg;

  bool get isNone => event == VoiceEvent.none;

  @override
  String toString() => 'VoiceEventRecord(${event.name}, arg: $arg)';
}

/// Snapshot of the route situation.
class VoiceRouteInfo {
  const VoiceRouteInfo({required this.available, required this.active});

  final Set<VoiceRoute> available;
  final VoiceRoute active;

  bool get hasEarpiece => available.contains(VoiceRoute.earpiece);

  @override
  String toString() =>
      'VoiceRouteInfo(active: ${active.logName}, '
      'available: ${available.map((r) => r.logName).join('|')})';
}

/// Thrown for every negative ABI return code that a caller cannot sensibly
/// ignore.
class VoiceSessionException implements Exception {
  const VoiceSessionException(this.code, this.operation);
  final int code;
  final String operation;

  @override
  String toString() =>
      'VoiceSessionException($operation: ${VoiceErr.describe(code)} [$code])';
}

// ─────────────────────────────────────────────────────────────────────────
// Native structs
// ─────────────────────────────────────────────────────────────────────────

final class _CVoiceSession extends Opaque {}

final class _CVoiceFormat extends Struct {
  @Int32()
  external int sampleRate;
  @Int32()
  external int channels;
  @Int32()
  external int frameSamples;
  @Int32()
  external int frameBytes;
}

final class _CVoiceReport extends Struct {
  external _CVoiceFormat format;
  @Int32()
  external int aecState;
  @Int32()
  external int nsState;
  @Int32()
  external int agcState;
  @Int32()
  external int chainOrigin;
  @Int32()
  external int backend;
  @Int32()
  external int duplex;
  @Int32()
  external int routeActiveIn;
  @Int32()
  external int routeActiveOut;
  @Int32()
  external int routesAvailableMask;

  // Erratum E6a. These two are not decoration: the C struct grew from 72 to 80
  // bytes when they were added, and a binding that omitted them would read
  // `underruns` out of the padding word and `overruns` out of `underruns` — the
  // report would look plausible and be wrong. The C header carries a
  // `_Static_assert` on 80 for exactly this reason.
  @Int32()
  external int micMuted;
  @Int32()
  external int outputMuted;

  @Int64()
  external int underruns;
  @Int64()
  external int overruns;
}

typedef _OpenNative = Pointer<_CVoiceSession> Function(Int32, Pointer<_CVoiceFormat>);
typedef _OpenDart = Pointer<_CVoiceSession> Function(int, Pointer<_CVoiceFormat>);

typedef _StartNative = Int32 Function(Pointer<_CVoiceSession>);
typedef _StartDart = int Function(Pointer<_CVoiceSession>);

typedef _VoidNative = Void Function(Pointer<_CVoiceSession>);
typedef _VoidDart = void Function(Pointer<_CVoiceSession>);

typedef _CaptureReadNative = Int32 Function(
    Pointer<_CVoiceSession>, Pointer<Int16>, Int32);
typedef _CaptureReadDart = int Function(
    Pointer<_CVoiceSession>, Pointer<Int16>, int);

typedef _PlaybackWriteNative = Int32 Function(
    Pointer<_CVoiceSession>, Pointer<Int16>, Int32);
typedef _PlaybackWriteDart = int Function(
    Pointer<_CVoiceSession>, Pointer<Int16>, int);

typedef _SetIntNative = Void Function(Pointer<_CVoiceSession>, Int32);
typedef _SetIntDart = void Function(Pointer<_CVoiceSession>, int);

typedef _SetRouteNative = Int32 Function(Pointer<_CVoiceSession>, Int32);
typedef _SetRouteDart = int Function(Pointer<_CVoiceSession>, int);

typedef _TwoIntOutNative = Int32 Function(
    Pointer<_CVoiceSession>, Pointer<Int32>, Pointer<Int32>);
typedef _TwoIntOutDart = int Function(
    Pointer<_CVoiceSession>, Pointer<Int32>, Pointer<Int32>);

typedef _GetReportNative = Void Function(
    Pointer<_CVoiceSession>, Pointer<_CVoiceReport>);
typedef _GetReportDart = void Function(
    Pointer<_CVoiceSession>, Pointer<_CVoiceReport>);

// ─────────────────────────────────────────────────────────────────────────
// Library loading
// ─────────────────────────────────────────────────────────────────────────

/// Resolves and binds `libcleona_voice` (or the mock).
///
/// The real backend and the mock export the **same** symbols, so a process
/// must never load both. Which one is used is therefore an explicit choice at
/// the call site ([VoiceNativeLibrary.platform] vs [VoiceNativeLibrary.mock])
/// rather than something the loader search order decides.
class VoiceNativeLibrary {
  VoiceNativeLibrary._(this._lib, this.baseName) {
    _open = _lib.lookupFunction<_OpenNative, _OpenDart>('cleona_voice_open');
    _start = _lib.lookupFunction<_StartNative, _StartDart>('cleona_voice_start');
    _stop = _lib.lookupFunction<_VoidNative, _VoidDart>('cleona_voice_stop');
    _closeSession =
        _lib.lookupFunction<_VoidNative, _VoidDart>('cleona_voice_close');
    _captureRead = _lib.lookupFunction<_CaptureReadNative, _CaptureReadDart>(
        'cleona_voice_capture_read');
    _playbackWrite =
        _lib.lookupFunction<_PlaybackWriteNative, _PlaybackWriteDart>(
            'cleona_voice_playback_write');
    _setMicMuted = _lib.lookupFunction<_SetIntNative, _SetIntDart>(
        'cleona_voice_set_mic_muted');
    _setOutputMuted = _lib.lookupFunction<_SetIntNative, _SetIntDart>(
        'cleona_voice_set_output_muted');
    _setRoute = _lib.lookupFunction<_SetRouteNative, _SetRouteDart>(
        'cleona_voice_set_route');
    _getRoutes = _lib.lookupFunction<_TwoIntOutNative, _TwoIntOutDart>(
        'cleona_voice_get_routes');
    _pollEvent = _lib.lookupFunction<_TwoIntOutNative, _TwoIntOutDart>(
        'cleona_voice_poll_event');
    _getReport = _lib.lookupFunction<_GetReportNative, _GetReportDart>(
        'cleona_voice_get_report');
  }

  /// Base name of the loaded library, e.g. `cleona_voice` or
  /// `cleona_voice_mock`. Goes into diagnostics so a test run can never be
  /// mistaken for a device run.
  final String baseName;

  final DynamicLibrary _lib;

  late final _OpenDart _open;
  late final _StartDart _start;
  late final _VoidDart _stop;
  late final _VoidDart _closeSession;
  late final _CaptureReadDart _captureRead;
  late final _PlaybackWriteDart _playbackWrite;
  late final _SetIntDart _setMicMuted;
  late final _SetIntDart _setOutputMuted;
  late final _SetRouteDart _setRoute;
  late final _TwoIntOutDart _getRoutes;
  late final _TwoIntOutDart _pollEvent;
  late final _GetReportDart _getReport;

  /// The real platform backend (V1.1-V1.4).
  static VoiceNativeLibrary platform() => _load('cleona_voice');

  /// The hardware-free mock (`native/cleona_voice/mock/`).
  ///
  /// Used by V1.5-V1.9, V1.12 and the UI work so they need no device.
  static VoiceNativeLibrary mock() => _load('cleona_voice_mock');

  static final Map<String, VoiceNativeLibrary> _cache = {};

  static VoiceNativeLibrary _load(String baseName) {
    final cached = _cache[baseName];
    if (cached != null) return cached;

    if (Platform.isIOS) {
      // Statically linked via CleonaNative.podspec, same as the other native
      // libraries. The symbols must be listed in
      // ios/CleonaNative/cleona_exported_symbols.txt or the linker dead-strips
      // them and the lookup below throws at runtime — see BUILD_REQUEST.md.
      final lib = VoiceNativeLibrary._(DynamicLibrary.process(), baseName);
      _cache[baseName] = lib;
      return lib;
    }

    final candidates = <String>[];
    if (Platform.isLinux) {
      candidates.add('lib$baseName.so');
      try {
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        candidates.add('$exeDir/lib/lib$baseName.so');
      } catch (_) {/* resolvedExecutable can throw in odd environments */}
      final home = Platform.environment['HOME'] ?? '';
      if (home.isNotEmpty) {
        candidates.add('$home/cleona-app/lib/lib$baseName.so');
      }
      // Build-tree fallback so `dart test` and the smoke runs work without
      // installing anything.
      candidates.add(
          '${Directory.current.path}/native/cleona_voice/build/lib$baseName.so');
    } else if (Platform.isAndroid) {
      candidates.add('lib$baseName.so'); // resolved by the Android linker
    } else if (Platform.isWindows) {
      candidates.add('$baseName.dll');
      try {
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        candidates.add('$exeDir\\$baseName.dll');
      } catch (_) {/* see above */}
    } else if (Platform.isMacOS) {
      candidates.add('$baseName.dylib');
      candidates.add('@executable_path/../Frameworks/$baseName.dylib');
    }

    Object? lastError;
    for (final c in candidates) {
      try {
        final lib = VoiceNativeLibrary._(DynamicLibrary.open(c), baseName);
        _cache[baseName] = lib;
        return lib;
      } catch (e) {
        lastError = e;
      }
    }
    throw StateError('$baseName not found. Searched: $candidates '
        '(last error: $lastError)');
  }
}

// ─────────────────────────────────────────────────────────────────────────
// VoiceSession
// ─────────────────────────────────────────────────────────────────────────

/// One OS duplex voice session (I2).
///
/// Lifecycle is explicit and symmetric: [open] → [start] → … → [stop] →
/// [close]. Every native allocation made by [open] is released by [close], and
/// [close] is idempotent.
class VoiceSession {
  VoiceSession._(this._lib, this._session, this._format) {
    _allocateBuffers();
  }

  final VoiceNativeLibrary _lib;
  Pointer<_CVoiceSession> _session;
  VoiceFormat _format;

  // Reusable native scratch. Allocated once per format so the 50 Hz hot path
  // does not allocate, and re-allocated only on EV_FORMAT_CHANGED.
  Pointer<Int16> _captureBuf = nullptr;
  Pointer<Int16> _playbackBuf = nullptr;
  final Pointer<Int32> _outA = calloc<Int32>();
  final Pointer<Int32> _outB = calloc<Int32>();
  final Pointer<_CVoiceReport> _reportBuf = calloc<_CVoiceReport>();

  bool _closed = false;
  bool _started = false;
  bool _micMuted = false;
  bool _outputMuted = false;

  /// The negotiated frame contract, as reported by the platform. Never a
  /// constant, never a guess (I3, I4).
  VoiceFormat get format => _format;

  bool get isStarted => _started;
  bool get isClosed => _closed;
  bool get micMuted => _micMuted;
  bool get outputMuted => _outputMuted;

  /// Which native library backs this session — `cleona_voice` on a device,
  /// `cleona_voice_mock` in tests.
  String get backendLibrary => _lib.baseName;

  /// Opens one OS duplex voice session.
  ///
  /// [rateHint] is a **hint**. A backend that cannot get it returns its own
  /// rate, and that is not an error (I3). Pass 0 for "no preference". Callers
  /// must read [format] afterwards and must never assume the hint was taken.
  ///
  /// Throws [VoiceSessionException] when the backend refuses; the reason is
  /// carried in-band in the format struct (see `cleona_voice.h`).
  static VoiceSession open({
    required VoiceNativeLibrary library,
    int rateHint = 0,
  }) {
    final fmtPtr = calloc<_CVoiceFormat>();
    try {
      final session = library._open(rateHint, fmtPtr);
      if (session == nullptr) {
        // The backend writes a negative CLEONA_VOICE_ERR_* into sample_rate
        // when open fails, so the caller can tell "no device" from "permission
        // denied" without a second call.
        final code = fmtPtr.ref.sampleRate;
        throw VoiceSessionException(code < 0 ? code : VoiceErr.backend, 'open');
      }
      final fmt = VoiceFormat(
        sampleRate: fmtPtr.ref.sampleRate,
        channels: fmtPtr.ref.channels,
        frameSamples: fmtPtr.ref.frameSamples,
        frameBytes: fmtPtr.ref.frameBytes,
      );
      if (!fmt.isSelfConsistent) {
        // Fail loudly rather than compute with a broken frame contract: every
        // buffer size in the call path derives from these four numbers.
        library._closeSession(session);
        throw VoiceSessionException(VoiceErr.backend,
            'open returned an inconsistent format: $fmt');
      }
      return VoiceSession._(library, session, fmt);
    } finally {
      calloc.free(fmtPtr);
    }
  }

  void _allocateBuffers() {
    _freeFrameBuffers();
    _captureBuf = calloc<Int16>(_format.frameSamples);
    _playbackBuf = calloc<Int16>(_format.frameSamples);
  }

  void _freeFrameBuffers() {
    if (_captureBuf != nullptr) {
      calloc.free(_captureBuf);
      _captureBuf = nullptr;
    }
    if (_playbackBuf != nullptr) {
      calloc.free(_playbackBuf);
      _playbackBuf = nullptr;
    }
  }

  void _requireOpen(String op) {
    if (_closed) throw VoiceSessionException(VoiceErr.closed, op);
  }

  /// Starts both directions of the session.
  void start() {
    _requireOpen('start');
    final rc = _lib._start(_session);
    if (rc < 0) throw VoiceSessionException(rc, 'start');
    _started = true;
  }

  /// Stops both directions. Idempotent. The session can be started again.
  void stop() {
    if (_closed) return;
    _lib._stop(_session);
    _started = false;
  }

  /// Releases the session and every native allocation. Idempotent.
  ///
  /// Must not race with a capture read — stop the capture loop first.
  void close() {
    if (_closed) return;
    _closed = true;
    _started = false;
    _lib._closeSession(_session);
    _session = nullptr;
    _freeFrameBuffers();
    calloc.free(_outA);
    calloc.free(_outB);
    calloc.free(_reportBuf);
  }

  /// Reads exactly one frame into [dest].
  ///
  /// [dest] must be exactly `format.frameSamples` long — the size the platform
  /// reported, not one this code chose (I4). A wrong length is an
  /// [ArgumentError] rather than a silent partial copy.
  ///
  /// Blocks for at most [timeoutMs]. While the microphone is muted, frames keep
  /// arriving on the same cadence, zeroed (I6) — "no frames" never means
  /// "muted".
  VoiceCaptureStatus readCaptureFrameInto(Int16List dest,
      {int timeoutMs = 100}) {
    _requireOpen('capture_read');
    if (dest.length != _format.frameSamples) {
      throw ArgumentError.value(
        dest.length,
        'dest.length',
        'must equal the negotiated frame size ${_format.frameSamples}',
      );
    }
    final rc = _lib._captureRead(_session, _captureBuf, timeoutMs);
    final status = VoiceCaptureStatus.fromWire(rc);
    if (status == VoiceCaptureStatus.frame) {
      dest.setAll(0, _captureBuf.asTypedList(_format.frameSamples));
    }
    return status;
  }

  /// Convenience wrapper around [readCaptureFrameInto].
  ///
  /// Allocates one [Int16List] per frame; prefer [readCaptureFrameInto] with a
  /// reused buffer in the 50 Hz capture loop.
  Int16List? readCaptureFrame({int timeoutMs = 100}) {
    final dest = Int16List(_format.frameSamples);
    return readCaptureFrameInto(dest, timeoutMs: timeoutMs) ==
            VoiceCaptureStatus.frame
        ? dest
        : null;
  }

  /// Hands one decoded frame to the OS playback side of the same session.
  ///
  /// Never blocks: pacing is the output device's job (I5). Returns the raw ABI
  /// code so a hot loop can decide for itself; use [writePlaybackFrame] to get
  /// an exception instead.
  int writePlaybackFrameRaw(Int16List pcm) {
    _requireOpen('playback_write');
    if (pcm.length != _format.frameSamples) {
      // Checked here as well as natively: rejecting early keeps a rate
      // mismatch a rate mismatch instead of turning it into a mystery two
      // layers down.
      return VoiceErr.frameSize;
    }
    _playbackBuf.asTypedList(_format.frameSamples).setAll(0, pcm);
    return _lib._playbackWrite(_session, _playbackBuf, _format.frameSamples);
  }

  /// As [writePlaybackFrameRaw], but throws on failure.
  void writePlaybackFrame(Int16List pcm) {
    final rc = writePlaybackFrameRaw(pcm);
    if (rc < 0) throw VoiceSessionException(rc, 'playback_write');
  }

  /// Microphone mute. The capture stream **stays open** and keeps running;
  /// frames are zeroed (I6).
  ///
  /// Stopping the stream instead diverges the adaptive filter and produces
  /// about a second of echo on unmute — the superseded C code knew this and
  /// kept draining the reference while muted (`cleona_audio.c:152-156`).
  set micMuted(bool muted) {
    _requireOpen('set_mic_muted');
    _lib._setMicMuted(_session, muted ? 1 : 0);
    _micMuted = muted;
  }

  /// Output mute ("sound off"), distinct from speakerphone. The playback
  /// stream stays open and renders silence; writes keep being accepted so the
  /// jitter buffer keeps draining normally (I6).
  set outputMuted(bool muted) {
    _requireOpen('set_output_muted');
    _lib._setOutputMuted(_session, muted ? 1 : 0);
    _outputMuted = muted;
  }

  /// Switches the active output route without tearing the stream down.
  ///
  /// Returns the raw ABI code. [VoiceErr.routeUnavailable] is the expected
  /// answer for [VoiceRoute.earpiece] on macOS, Windows and Linux — those
  /// platforms have no earpiece, and the UI reacts with a device chooser
  /// instead of a speakerphone button that does nothing.
  ///
  /// The I7 rule ("when the active route disappears, fall back to the
  /// earpiece, never the speaker") is policy and lives in `RoutePolicy`
  /// (V1.5), not here. This method only makes the switch executable and its
  /// failure visible.
  int setRoute(VoiceRoute route) {
    _requireOpen('set_route');
    return _lib._setRoute(_session, route.wireValue);
  }

  /// As [setRoute], but throws on failure.
  void setRouteOrThrow(VoiceRoute route) {
    final rc = setRoute(route);
    if (rc < 0) throw VoiceSessionException(rc, 'set_route(${route.logName})');
  }

  /// Current route set and active output route.
  VoiceRouteInfo getRoutes() {
    _requireOpen('get_routes');
    final rc = _lib._getRoutes(_session, _outA, _outB);
    if (rc < 0) throw VoiceSessionException(rc, 'get_routes');
    return VoiceRouteInfo(
      available: VoiceRoute.decodeMask(_outA.value),
      active: VoiceRoute.fromWire(_outB.value),
    );
  }

  /// Dequeues at most one event. Non-blocking; returns [VoiceEvent.none] when
  /// nothing is pending, which is the normal case and not an error.
  ///
  /// A [VoiceEvent.formatChanged] event is acted on here before it is handed
  /// back: the format is re-read and the native buffers are resized, so a
  /// caller that ignores the event still cannot end up reading with a stale
  /// frame size (I3/I4). Callers that care — the jitter buffer, the codec —
  /// still see the event and can re-derive their own sizes from [format].
  VoiceEventRecord pollEvent() {
    _requireOpen('poll_event');
    final rc = _lib._pollEvent(_session, _outA, _outB);
    if (rc < 0) throw VoiceSessionException(rc, 'poll_event');
    final record =
        VoiceEventRecord(VoiceEvent.fromWire(_outA.value), _outB.value);
    if (record.event == VoiceEvent.formatChanged) {
      refreshFormat();
    }
    return record;
  }

  /// Re-reads the negotiated format from the backend and resizes the native
  /// scratch buffers.
  ///
  /// Called automatically on [VoiceEvent.formatChanged]; exposed because a
  /// backend may also renegotiate across a [stop]/[start] pair.
  void refreshFormat() {
    _requireOpen('refresh_format');
    _lib._getReport(_session, _reportBuf);
    final f = _reportBuf.ref.format;
    final updated = VoiceFormat(
      sampleRate: f.sampleRate,
      channels: f.channels,
      frameSamples: f.frameSamples,
      frameBytes: f.frameBytes,
    );
    if (!updated.isSelfConsistent) {
      throw VoiceSessionException(
          VoiceErr.backend, 'refresh_format: inconsistent format $updated');
    }
    if (updated.frameSamples != _format.frameSamples) {
      _format = updated;
      _allocateBuffers();
    } else {
      _format = updated;
    }
  }

  /// The verification report (I11).
  ///
  /// Converts what the backend said, and nothing more. Log it exactly once per
  /// call through `VoiceReportLogger` — which requires a `profileDir`, so the
  /// line cannot silently land nowhere the way `VideoEngine`'s did.
  VoiceReport getReport() {
    _requireOpen('get_report');
    _lib._getReport(_session, _reportBuf);
    final r = _reportBuf.ref;
    return VoiceReport(
      format: VoiceFormat(
        sampleRate: r.format.sampleRate,
        channels: r.format.channels,
        frameSamples: r.format.frameSamples,
        frameBytes: r.format.frameBytes,
      ),
      aec: VoiceEffectState.fromWire(r.aecState),
      ns: VoiceEffectState.fromWire(r.nsState),
      agc: VoiceEffectState.fromWire(r.agcState),
      chainOrigin: VoiceChainOrigin.fromWire(r.chainOrigin),
      backend: VoiceBackend.fromWire(r.backend),
      duplex: r.duplex == 1,
      routeActiveIn: VoiceRoute.fromWire(r.routeActiveIn),
      routeActiveOut: VoiceRoute.fromWire(r.routeActiveOut),
      routesAvailable: VoiceRoute.decodeMask(r.routesAvailableMask),
      underruns: r.underruns,
      overruns: r.overruns,
      rawWireValues: {
        'aec': r.aecState,
        'ns': r.nsState,
        'agc': r.agcState,
        'chain_origin': r.chainOrigin,
        'backend': r.backend,
        'duplex': r.duplex,
        'route_active_in': r.routeActiveIn,
        'route_active_out': r.routeActiveOut,
        'routes_available_mask': r.routesAvailableMask,
        // Erratum E6a. Carried as raw wire values because `VoiceReport` has no
        // typed fields for them yet — that is work package V1.7, which owns
        // `voice_report.dart`. Until V1.7 lands, this map is the only Dart-side
        // access to what the backend said about its mute state, and it is
        // already enough for a test to assert §10.4 ("the mute states survive
        // route changes") without waiting for the typed API.
        'mic_muted': r.micMuted,
        'output_muted': r.outputMuted,
      },
    );
  }
}
