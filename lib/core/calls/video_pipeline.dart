/// Dart binding for `native/cleona_video/cleona_video.h` — the single boundary
/// between Cleona and every platform video stack.
///
/// Work package V0.3 of `docs/SPEC_VOICE_VIDEO_REWORK.md`. Authoritative
/// background: `Cleona_Chat_Architecture_v3_0.md` §10.6 and §10.3.1.
///
/// ## No pixels in Dart (I10)
///
/// This file moves exactly two things across the FFI boundary: an **encoded
/// bitstream** and an opaque **texture id**. Camera frames go
/// camera -> platform surface -> hardware encoder without ever entering the
/// Dart heap, and decoded frames go decoder -> texture -> Flutter the same way.
///
/// That is what removes the five per-frame conversions the superseded stack ran
/// 30 times a second on the UI isolate: I420 rotation, preview mirroring,
/// I420 -> RGBA for the local preview, I420 -> RGBA for the remote picture, and
/// a `decodeImageFromPixels` call per frame with a manual `dispose` (§10.6).
///
/// ## No `dart:ui` (deliberate, and load-bearing)
///
/// This library imports `dart:ffi`, `dart:io`, `dart:typed_data` and
/// `package:ffi` — nothing else. In particular **no `dart:ui` and no
/// `package:flutter`**.
///
/// That is not tidiness. The superseded `VideoEngine` imported `dart:ui`, which
/// forced it behind a factory only the Flutter process wires up. On Linux and
/// Windows `CleonaService` runs in a separate daemon, `_wireServiceCallbacks`
/// is never called there, `createVideoEngine` stays null, and every desktop
/// video call silently degrades to audio-only. The code says so itself
/// (`lib/main.dart:2163-2171`). Adding a `dart:ui` import here re-creates that
/// gap — the daemon cannot load this file any more, and desktop video is gone
/// again before it ever existed.
///
/// A texture id is an `int`. It does not need `dart:ui` to travel; only the
/// widget that finally displays it does, and that widget lives in the UI layer.
///
/// ## Live-media constraints this binding carries (I8, I9)
///
/// Live media is plain UDP, fire-and-forget, and exempt from TLS escalation and
/// from NACK-based fragment recovery (§10.3.1). A frame therefore has to *fit*
/// the plain-UDP delivery envelope. [VideoConfig.maxFrameBytes] carries that
/// ceiling down to the encoder. Enforcing the exemption in the transport itself
/// is package V1.11 and is not this file's job — but the number that makes the
/// exemption survivable is passed from here.
///
/// **Erratum 1: the ceiling moves, and silence is never the answer.** It is
/// derived from the running bandwidth estimate, not fixed at [VideoPipeline.open],
/// and is pushed down with [VideoPipeline.reconfigure]. There are exactly two
/// correct responses to a link that degrades:
///
/// 1. scale down and keep sending — [VideoReconfigureAccepted];
/// 2. nothing fits any more — [VideoRateUnachievable], on which the caller
///    switches own video off **and tells the user why**, locally and at the
///    peer (V1.12 `CALL_MEDIA_STATE`).
///
/// There is no third response. [VideoReport.framesDroppedOversize] is
/// consequently a defect counter that must read 0 in the field, not a working
/// safety net.
///
/// **Erratum 6b: [VideoPipeline.open] says why it failed.** Erratum 1's promise
/// only holds if the reason exists at *every* entry point. `cleona_video_open`
/// returns a pointer and used to answer NULL for "the caller got it wrong" and
/// for "this link cannot carry video" alike, so a caller could show no text or
/// the wrong one — the very failure Erratum 1 removes. The native ABI now
/// carries the reason in-band in `out_negotiated->max_frame_bytes`, and this
/// binding turns it into the sealed [VideoOpenOutcome]: exactly as with
/// [VideoPipeline.reconfigure], the link condition is a value the caller must
/// handle, and a caller bug stays an exception.
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

// ── ABI constants — keep in lockstep with cleona_video.h ─────────────

/// Codec ids. H.264 Constrained Baseline is the mandatory interop level; the
/// reasoning is recorded in architecture §10.6 ("Codec decision") and is not
/// re-opened here.
enum VideoCodec {
  h264(1),
  hevc(2),
  av1(3),
  vp9(4);

  const VideoCodec(this.id);
  final int id;

  static VideoCodec? fromId(int id) {
    for (final c in VideoCodec.values) {
      if (c.id == id) return c;
    }
    return null;
  }
}

/// Bit set on an intra-coded frame a decoder can start from.
const int kVideoFlagKeyframe = 0x01;

// Return codes (cleona_video.h).
const int _kOk = 0;
const int _kErrInvalid = -1;
const int _kErrState = -2;
const int _kErrUnsupported = -3;
const int _kErrBackend = -4;
const int _kErrBufferTooSmall = -5;
const int _kErrDecode = -6;
const int _kErrRateUnachievable = -7;

const int _kReadFrame = 1;
const int _kReadTimeout = 0;

const int _kSubmitAccepted = 0;
const int _kSubmitAwaitingKeyframe = 1;

/// Value of [VideoReport.hardwareEncode] / [VideoReport.hardwareDecode] when
/// the backend could not determine the answer. I11: a legitimate answer.
/// Reporting hardware acceleration that was never verified is not.
const int kVideoHardwareNotDeterminable = -1;

/// Backend ids reported in [VideoReport]. Mirrors `CLEONA_VIDEO_BACKEND_*`.
const Map<int, String> kVideoBackendNames = <int, String>{
  0: 'none',
  1: 'mock',
  2: 'android_camerax',
  3: 'android_mediacodec',
  4: 'apple_avcapture',
  5: 'apple_videotoolbox',
  6: 'win_mf_sourcereader',
  7: 'win_mf_transform',
  8: 'linux_v4l2',
  9: 'linux_pipewire',
  10: 'linux_vaapi',
  11: 'linux_v4l2_m2m',
};

// ── Native struct layouts ────────────────────────────────────────────

final class _NativeConfig extends Struct {
  @Int32()
  external int codec;
  @Int32()
  external int width;
  @Int32()
  external int height;
  @Int32()
  external int fps;
  @Int32()
  external int targetBitrateKbps;
  @Int32()
  external int maxFrameBytes;
  @Int32()
  external int keyframeIntervalFrames;
}

final class _NativeReport extends Struct {
  @Int32()
  external int codecInUse;
  @Int32()
  external int hardwareEncode;
  @Int32()
  external int hardwareDecode;
  @Int32()
  external int negotiatedWidth;
  @Int32()
  external int negotiatedHeight;
  @Int32()
  external int negotiatedFps;
  @Int32()
  external int captureBackend;
  @Int32()
  external int encodeBackend;
  @Int64()
  external int framesCaptured;
  @Int64()
  external int framesEncoded;
  @Int64()
  external int framesDroppedOversize;
  @Int64()
  external int framesDecoded;
  @Int64()
  external int decodeFailures;
}

// ── Native function signatures ───────────────────────────────────────

typedef _OpenNative = Pointer<Void> Function(
    Pointer<_NativeConfig>, Pointer<_NativeConfig>);
typedef _OpenDart = Pointer<Void> Function(
    Pointer<_NativeConfig>, Pointer<_NativeConfig>);

typedef _SessionInt32Native = Int32 Function(Pointer<Void>);
typedef _SessionInt32Dart = int Function(Pointer<Void>);

typedef _SessionVoidNative = Void Function(Pointer<Void>);
typedef _SessionVoidDart = void Function(Pointer<Void>);

typedef _ReadNative = Int32 Function(Pointer<Void>, Pointer<Uint8>, Int32,
    Pointer<Int32>, Pointer<Int32>, Pointer<Int64>, Int32);
typedef _ReadDart = int Function(Pointer<Void>, Pointer<Uint8>, int,
    Pointer<Int32>, Pointer<Int32>, Pointer<Int64>, int);

typedef _SubmitNative = Int32 Function(
    Pointer<Void>, Pointer<Uint8>, Int32, Int32);
typedef _SubmitDart = int Function(Pointer<Void>, Pointer<Uint8>, int, int);

typedef _TextureNative = Int32 Function(Pointer<Void>, Pointer<Int64>);
typedef _TextureDart = int Function(Pointer<Void>, Pointer<Int64>);

typedef _SetEnabledNative = Void Function(Pointer<Void>, Int32);
typedef _SetEnabledDart = void Function(Pointer<Void>, int);

typedef _ReportNative = Void Function(Pointer<Void>, Pointer<_NativeReport>);
typedef _ReportDart = void Function(Pointer<Void>, Pointer<_NativeReport>);

typedef _ReconfigureNative = Int32 Function(
    Pointer<Void>, Pointer<_NativeConfig>, Pointer<_NativeConfig>);
typedef _ReconfigureDart = int Function(
    Pointer<Void>, Pointer<_NativeConfig>, Pointer<_NativeConfig>);

// ── Value types ──────────────────────────────────────────────────────

/// A video configuration, on the way in a request and on the way out the
/// backend's answer.
///
/// The backend may negotiate every field **down** and never up. Always read the
/// negotiated result back from [VideoPipeline.negotiated] rather than assuming
/// the request was granted.
class VideoConfig {
  const VideoConfig({
    this.codec = VideoCodec.h264,
    required this.width,
    required this.height,
    required this.fps,
    required this.targetBitrateKbps,
    required this.maxFrameBytes,
    this.keyframeIntervalFrames = 0,
  });

  /// Preferred codec. If the backend has no hardware for it, it negotiates
  /// down to [VideoCodec.h264] — that is not a failure.
  final VideoCodec codec;

  final int width;
  final int height;
  final int fps;

  /// Target for the hardware rate controller. Cleona's bandwidth estimator
  /// sets it; Cleona does not do rate control itself (§10.6).
  final int targetBitrateKbps;

  /// I9: hard ceiling per encoded frame, so a live-media frame fits the
  /// plain-UDP delivery envelope (§10.3.1).
  ///
  /// The value comes from the transport layer (package V1.11) and from the
  /// running bandwidth estimate — not from taste, and not from a constant in
  /// this file. It is **not fixed for the session** (Erratum 1); push a new one
  /// with [VideoPipeline.reconfigure] whenever the estimate moves.
  ///
  /// Must be > 0 — a session without a ceiling would violate I9 by
  /// construction, and both [VideoPipeline.open] and [VideoPipeline.reconfigure]
  /// reject it.
  final int maxFrameBytes;

  /// Upper bound on the frames between keyframes. 0 = backend default.
  final int keyframeIntervalFrames;

  VideoConfig copyWith({
    VideoCodec? codec,
    int? width,
    int? height,
    int? fps,
    int? targetBitrateKbps,
    int? maxFrameBytes,
    int? keyframeIntervalFrames,
  }) {
    return VideoConfig(
      codec: codec ?? this.codec,
      width: width ?? this.width,
      height: height ?? this.height,
      fps: fps ?? this.fps,
      targetBitrateKbps: targetBitrateKbps ?? this.targetBitrateKbps,
      maxFrameBytes: maxFrameBytes ?? this.maxFrameBytes,
      keyframeIntervalFrames:
          keyframeIntervalFrames ?? this.keyframeIntervalFrames,
    );
  }

  @override
  String toString() => 'VideoConfig(${codec.name} ${width}x$height@$fps '
      '${targetBitrateKbps}kbps maxFrame=$maxFrameBytes '
      'kfInterval=$keyframeIntervalFrames)';
}

/// One encoded frame on its way to the wire. No pixels — I10.
class EncodedVideoFrame {
  const EncodedVideoFrame({
    required this.data,
    required this.flags,
    required this.ptsUs,
  });

  /// The encoded bitstream, ready to be encrypted and sent.
  final Uint8List data;

  /// Bitmask of `kVideoFlag*`.
  final int flags;

  /// Presentation timestamp in microseconds on the capture clock. Strictly
  /// increasing across the frames of one session.
  final int ptsUs;

  bool get isKeyframe => (flags & kVideoFlagKeyframe) != 0;

  @override
  String toString() =>
      'EncodedVideoFrame(${data.length}B key=$isKeyframe pts=${ptsUs}us)';
}

/// Outcome of handing a peer's frame to the decoder.
enum VideoSubmitResult {
  /// Queued for decode.
  accepted,

  /// Deliberately not decoded: no keyframe has been seen on this session yet
  /// and this frame is not one. Not a failure, and not counted in
  /// [VideoReport.decodeFailures]. Ask the peer for a keyframe.
  awaitingKeyframe,

  /// The decoder rejected the bitstream. Counted in
  /// [VideoReport.decodeFailures].
  decodeError,
}

/// Outcome of [VideoPipeline.reconfigure] — Erratum 1.
///
/// Deliberately a sealed type rather than a return code or a thrown exception:
/// the two cases are not "success and failure", they are **two different things
/// the caller has to do**, and Dart's exhaustive `switch` makes skipping one a
/// compile error.
///
/// ```dart
/// switch (pipeline.reconfigure(next)) {
///   case VideoReconfigureAccepted(:final negotiated):
///     bandwidthEstimator.note(negotiated.targetBitrateKbps);
///   case VideoRateUnachievable(:final reason):
///     pipeline.captureEnabled = false;   // stop own video …
///     showVideoOffReason(reason);        // … and say why. Never go quiet.
/// }
/// ```
///
/// A generic exception would collapse "not right now" and "not at all on this
/// link" into one branch, and the user-facing text hangs on exactly that
/// distinction.
sealed class VideoReconfigureOutcome {
  const VideoReconfigureOutcome();
}

/// The backend accepted the new configuration. [negotiated] is authoritative
/// and is usually smaller than what was requested — the backend may settle
/// every field downwards and never upwards.
final class VideoReconfigureAccepted extends VideoReconfigureOutcome {
  const VideoReconfigureAccepted(this.negotiated);
  final VideoConfig negotiated;

  @override
  String toString() => 'VideoReconfigureAccepted($negotiated)';
}

/// No supported step — not the lowest resolution, not the lowest bitrate —
/// produces frames that fit under the requested ceiling.
///
/// The session is **unchanged** and still running with its previous
/// configuration. The caller stops own video and shows the user [reason]; it
/// does not retry silently. Going quiet without an explanation is the failure
/// this whole path exists to remove.
final class VideoRateUnachievable extends VideoReconfigureOutcome {
  const VideoRateUnachievable({
    required this.requested,
    required this.stillRunningWith,
  });

  /// What was asked for and could not be met.
  final VideoConfig requested;

  /// What the session is still configured with. Video is not off yet — that is
  /// the caller's decision, and its consequence is a message on screen.
  final VideoConfig stillRunningWith;

  /// A short, loggable reason. The user-facing wording and its translation
  /// belong to the UI package (V1.6), not here.
  String get reason =>
      'link too slow for video: no supported encoder step fits '
      '${requested.maxFrameBytes} bytes per frame';

  @override
  String toString() => 'VideoRateUnachievable($reason)';
}

/// Outcome of [VideoPipeline.open] — Erratum 6b.
///
/// Modelled on [VideoReconfigureOutcome], and split along the same line: the
/// sealed type carries only the outcomes the caller has to *act on differently*,
/// and a caller bug stays an exception. Opening a session can fail for four
/// reasons (see `cleona_video.h`, Erratum 6b), but only one of them produces a
/// sentence for the user:
///
/// * `ERR_RATE_UNACHIEVABLE` — the link cannot carry video. Not a bug, not
///   retryable by fixing the call: [VideoOpenRateUnachievable], and the caller
///   tells the user why. This is the branch Erratum 1 requires and the reason
///   this type exists.
/// * `ERR_INVALID` — the configuration was wrong. A programming error; the same
///   call fails again. [VideoPipelineException].
/// * `ERR_UNSUPPORTED` / `ERR_BACKEND` — no video path on this device, or this
///   attempt failed. The caller degrades to audio-only; there is no
///   link-specific text to show. [VideoPipelineException].
///
/// ```dart
/// switch (VideoPipeline.open(cfg)) {
///   case VideoOpenAccepted(:final pipeline):
///     pipeline.start();
///   case VideoOpenRateUnachievable(:final reason):
///     showVideoOffReason(reason);   // never go quiet — Erratum 1
/// }
/// ```
///
/// An exhaustive `switch` makes skipping the second branch a compile error,
/// which is the whole point: a caller that only ever saw a thrown exception
/// would have no way to tell "I called this wrong" from "this link is too slow",
/// and would show the wrong text or none.
sealed class VideoOpenOutcome {
  const VideoOpenOutcome();
}

/// The backend opened a session. [pipeline] owns native resources and must be
/// closed.
final class VideoOpenAccepted extends VideoOpenOutcome {
  const VideoOpenAccepted(this.pipeline);
  final VideoPipeline pipeline;

  @override
  String toString() => 'VideoOpenAccepted(${pipeline.negotiated})';
}

/// The configuration was well-formed, but no supported encoder step — not the
/// lowest resolution, not the lowest bitrate — produces frames that fit under
/// [requested]'s `maxFrameBytes`.
///
/// No session exists, so there is nothing to close and nothing still running.
/// The caller does not start video and shows the user [reason]. Retrying with
/// the same ceiling is pointless; retrying after the bandwidth estimate rises
/// is the correct move.
final class VideoOpenRateUnachievable extends VideoOpenOutcome {
  const VideoOpenRateUnachievable({required this.requested});

  /// What was asked for and could not be met.
  final VideoConfig requested;

  /// A short, loggable reason. The user-facing wording and its translation
  /// belong to the UI package (V1.6), not here.
  String get reason =>
      'link too slow for video: no supported encoder step fits '
      '${requested.maxFrameBytes} bytes per frame';

  @override
  String toString() => 'VideoOpenRateUnachievable($reason)';
}

/// The verification report — a normative part of the ABI, not a debug extra
/// (I11). V1.7 logs exactly one of these per call.
class VideoReport {
  const VideoReport({
    required this.codecInUse,
    required this.hardwareEncode,
    required this.hardwareDecode,
    required this.negotiatedWidth,
    required this.negotiatedHeight,
    required this.negotiatedFps,
    required this.captureBackend,
    required this.encodeBackend,
    required this.framesCaptured,
    required this.framesEncoded,
    required this.framesDroppedOversize,
    required this.framesDecoded,
    required this.decodeFailures,
  });

  final int codecInUse;

  /// 1 = yes, 0 = no, [kVideoHardwareNotDeterminable] = the backend could not
  /// tell. Never treat -1 as yes.
  final int hardwareEncode;
  final int hardwareDecode;

  final int negotiatedWidth;
  final int negotiatedHeight;
  final int negotiatedFps;

  final int captureBackend;
  final int encodeBackend;

  final int framesCaptured;

  /// Every frame the encoder produced, including those the I9 backstop
  /// discarded.
  final int framesEncoded;

  /// Frames discarded because they exceeded [VideoConfig.maxFrameBytes].
  ///
  /// **A defect counter, not a working mechanism** (Erratum 1). The two correct
  /// responses to a shrinking ceiling are [VideoReconfigureAccepted] (scale
  /// down, keep sending) and [VideoRateUnachievable] (stop, with a reason shown
  /// to the user). Discarding is neither: the peer sees a gap that nobody
  /// explained. In the field this must read 0 — assert on it in E2E rather than
  /// normalising it.
  ///
  /// One bounded exception: a [VideoPipeline.reconfigure] that lowers the
  /// ceiling while a frame is already encoded and waiting discards that one
  /// frame and counts it. At most one per reconfigure. A value that tracks the
  /// number of reconfigures is that exception; a value that grows with the
  /// frame rate is the defect.
  final int framesDroppedOversize;

  final int framesDecoded;

  /// Bitstreams the decoder rejected. Does not include frames skipped while
  /// waiting for a keyframe — those are not failures.
  final int decodeFailures;

  /// Frames actually handed to the caller.
  int get framesDelivered => framesEncoded - framesDroppedOversize;

  String get codecName => VideoCodec.fromId(codecInUse)?.name ?? 'unknown';
  String get captureBackendName =>
      kVideoBackendNames[captureBackend] ?? 'unknown($captureBackend)';
  String get encodeBackendName =>
      kVideoBackendNames[encodeBackend] ?? 'unknown($encodeBackend)';

  static String _hw(int v) => switch (v) {
        1 => 'yes',
        0 => 'no',
        kVideoHardwareNotDeterminable => 'not_determinable',
        _ => 'invalid($v)',
      };

  /// The single log line of V1.7. Deliberately flat and greppable.
  String toLogLine() => 'video_report codec=$codecName '
      '${negotiatedWidth}x$negotiatedHeight@$negotiatedFps '
      'hw_encode=${_hw(hardwareEncode)} hw_decode=${_hw(hardwareDecode)} '
      'capture=$captureBackendName encode=$encodeBackendName '
      'captured=$framesCaptured encoded=$framesEncoded '
      'dropped_oversize=$framesDroppedOversize '
      'decoded=$framesDecoded decode_failures=$decodeFailures';

  @override
  String toString() => toLogLine();
}

// ── Exceptions ───────────────────────────────────────────────────────

/// The native video library could not be loaded. The caller degrades to
/// audio-only; it never guesses that video works.
class VideoLibraryNotAvailable implements Exception {
  VideoLibraryNotAvailable(this.message);
  final String message;
  @override
  String toString() => 'VideoLibraryNotAvailable: $message';
}

/// A call into the video ABI failed.
class VideoPipelineException implements Exception {
  VideoPipelineException(this.message, {this.code});
  final String message;
  final int? code;
  @override
  String toString() => code == null
      ? 'VideoPipelineException: $message'
      : 'VideoPipelineException: $message (code $code)';
}

// ── Library loading ──────────────────────────────────────────────────

/// Resolves and holds the native video library.
///
/// Search order:
///   1. an explicit path passed by the caller,
///   2. the `CLEONA_VIDEO_LIB` environment variable (tests point this at the
///      mock),
///   3. the platform's default names next to the executable.
///
/// On iOS everything is statically linked into the process image, so
/// [DynamicLibrary.process] is the only correct answer — the same rule the rest
/// of the repo follows.
class VideoNativeLibrary {
  VideoNativeLibrary._(this._lib, this.path);

  final DynamicLibrary _lib;

  /// Where the library was found. `'<process>'` on iOS.
  final String path;

  static VideoNativeLibrary? _cached;

  /// Loads the library, once per process unless [libraryPath] differs.
  static VideoNativeLibrary load({String? libraryPath}) {
    final cached = _cached;
    if (cached != null && (libraryPath == null || cached.path == libraryPath)) {
      return cached;
    }

    if (libraryPath == null && Platform.isIOS) {
      final lib = VideoNativeLibrary._(DynamicLibrary.process(), '<process>');
      _cached = lib;
      return lib;
    }

    final tried = <String>[];
    for (final candidate in _searchPaths(libraryPath)) {
      tried.add(candidate);
      try {
        final lib = VideoNativeLibrary._(DynamicLibrary.open(candidate), candidate);
        // Fail loudly here rather than at the first frame: a library without
        // cleona_video_open is not this ABI.
        lib._lib.lookup<NativeFunction<_OpenNative>>('cleona_video_open');
        _cached = lib;
        return lib;
      } catch (_) {
        continue;
      }
    }
    throw VideoLibraryNotAvailable(
        'no cleona_video backend found; tried: ${tried.join(", ")}');
  }

  /// Drops the cached handle. Tests use this to switch backends.
  static void resetCache() => _cached = null;

  static List<String> _searchPaths(String? explicit) {
    if (explicit != null) return <String>[explicit];

    final fromEnv = Platform.environment['CLEONA_VIDEO_LIB'];
    if (fromEnv != null && fromEnv.isNotEmpty) return <String>[fromEnv];

    final sep = Platform.isWindows ? '\\' : '/';
    final exe = Platform.resolvedExecutable;
    final lastSep = exe.lastIndexOf(sep);
    final exeDir = lastSep > 0 ? exe.substring(0, lastSep) : '.';

    if (Platform.isMacOS) {
      return <String>[
        'libcleona_video.dylib',
        '$exeDir/libcleona_video.dylib',
        '$exeDir/../Frameworks/libcleona_video.dylib',
      ];
    }
    if (Platform.isWindows) {
      return <String>[
        'cleona_video.dll',
        '$exeDir\\cleona_video.dll',
        '$exeDir\\native\\cleona_video.dll',
      ];
    }
    // Linux + Android.
    return <String>[
      'libcleona_video.so',
      '$exeDir/libcleona_video.so',
      '$exeDir/lib/libcleona_video.so',
    ];
  }
}

// ── The pipeline ─────────────────────────────────────────────────────

/// One video session: capture + encode outbound, decode + render inbound.
///
/// Nothing in this class touches pixels (I10). [readEncoded] returns a
/// bitstream, [submitEncoded] takes one, and [textureId] is an opaque integer
/// the UI layer hands to a `Texture` widget.
///
/// Threading follows the ABI: at most one isolate may call [readEncoded] and at
/// most one may call [submitEncoded] concurrently; control and report calls are
/// free. [close] must not race with anything else on the same instance.
class VideoPipeline {
  VideoPipeline._(this._lib, this._session, this._negotiated) {
    _readBuf = calloc<Uint8>(_negotiated.maxFrameBytes);
    _readBufCap = _negotiated.maxFrameBytes;
    _outSize = calloc<Int32>();
    _outFlags = calloc<Int32>();
    _outPts = calloc<Int64>();
    _outTexture = calloc<Int64>();
    _reportPtr = calloc<_NativeReport>();
  }

  final VideoNativeLibrary _lib;
  Pointer<Void> _session;

  VideoConfig _negotiated;

  /// What the backend actually agreed to. Every field may be smaller than
  /// requested and is never larger.
  ///
  /// **Not fixed for the lifetime of the session** (Erratum 1): a successful
  /// [reconfigure] replaces it. Anything that caches a value from here — a read
  /// buffer size, a UI label, a bandwidth target — has to re-read it after
  /// every reconfigure.
  VideoConfig get negotiated => _negotiated;

  bool _closed = false;
  bool _running = false;

  late Pointer<Uint8> _readBuf;
  late int _readBufCap;
  late Pointer<Int32> _outSize;
  late Pointer<Int32> _outFlags;
  late Pointer<Int64> _outPts;
  late Pointer<Int64> _outTexture;
  late Pointer<_NativeReport> _reportPtr;

  Pointer<Uint8>? _submitBuf;
  int _submitBufCap = 0;

  /// Argument checks shared by [open] and [reconfigure]. These are caller bugs,
  /// not link conditions, and are therefore exceptions rather than an outcome
  /// the caller branches on.
  static void _validate(VideoConfig config) {
    if (config.maxFrameBytes <= 0) {
      // I9 is not optional. Catch it here so the failure names the reason
      // instead of surfacing as a bare NULL or a bare -1 from the backend.
      throw VideoPipelineException(
          'maxFrameBytes must be > 0 — a live-media frame has to fit the '
          'plain-UDP envelope (I9, architecture 10.3.1)');
    }
    if (config.width <= 0 || config.height <= 0 || config.fps <= 0) {
      throw VideoPipelineException('width, height and fps must be > 0');
    }
    if (config.targetBitrateKbps <= 0) {
      throw VideoPipelineException('targetBitrateKbps must be > 0');
    }
    if (config.keyframeIntervalFrames < 0) {
      throw VideoPipelineException('keyframeIntervalFrames must be >= 0');
    }
  }

  static void _writeConfig(Pointer<_NativeConfig> p, VideoConfig c) {
    p.ref
      ..codec = c.codec.id
      ..width = c.width
      ..height = c.height
      ..fps = c.fps
      ..targetBitrateKbps = c.targetBitrateKbps
      ..maxFrameBytes = c.maxFrameBytes
      ..keyframeIntervalFrames = c.keyframeIntervalFrames;
  }

  static VideoConfig _readConfig(Pointer<_NativeConfig> p) {
    final n = p.ref;
    return VideoConfig(
      codec: VideoCodec.fromId(n.codec) ?? VideoCodec.h264,
      width: n.width,
      height: n.height,
      fps: n.fps,
      targetBitrateKbps: n.targetBitrateKbps,
      maxFrameBytes: n.maxFrameBytes,
      keyframeIntervalFrames: n.keyframeIntervalFrames,
    );
  }

  /// Opens a session and negotiates [config].
  ///
  /// The caller **must** branch on the result — see [VideoOpenOutcome].
  /// [VideoOpenRateUnachievable] is not a logging matter: video does not start,
  /// *and the user is told why* (Erratum 1). Going quiet is what this path
  /// exists to remove.
  ///
  /// Throws [VideoLibraryNotAvailable] when no backend is present, and
  /// [VideoPipelineException] for the failures that carry no link-specific text:
  /// an invalid configuration (a caller bug), a device with no video path at
  /// all, and a backend that failed this attempt. The caller degrades to
  /// audio-only on those; it never proceeds as if video worked.
  static VideoOpenOutcome open(VideoConfig config, {String? libraryPath}) {
    _validate(config);

    final lib = VideoNativeLibrary.load(libraryPath: libraryPath);
    final open = lib._lib.lookupFunction<_OpenNative, _OpenDart>('cleona_video_open');

    final inPtr = calloc<_NativeConfig>();
    final outPtr = calloc<_NativeConfig>();
    try {
      _writeConfig(inPtr, config);

      final session = open(inPtr, outPtr);
      if (session == nullptr) {
        // Erratum 6b: a failed open() writes a negative CLEONA_VIDEO_ERR_* into
        // out_negotiated.maxFrameBytes and zeroes the rest. The field is
        // unambiguous because a value <= 0 is never a valid configuration —
        // open() fails closed on exactly that.
        //
        // `outPtr` was calloc'd, so a backend that writes nothing leaves 0.
        // That is not a code any conformant backend produces, and it is handled
        // below rather than guessed at: guessing would put the wrong sentence
        // on the user's screen, which is the bug this erratum fixes.
        final code = outPtr.ref.maxFrameBytes;
        switch (code) {
          case _kErrRateUnachievable:
            // The link, not the caller. The one branch that produces a text.
            return VideoOpenRateUnachievable(requested: config);
          case _kErrInvalid:
            throw VideoPipelineException(
                'backend rejected the configuration as invalid: $config',
                code: code);
          case _kErrUnsupported:
            throw VideoPipelineException(
                'this device has no video capture/encode path at all',
                code: code);
          case _kErrBackend:
            throw VideoPipelineException(
                'the video backend failed to open this session: $config',
                code: code);
          default:
            throw VideoPipelineException(
                'open failed and the backend named no reason '
                '(maxFrameBytes=$code on failure; a backend predating '
                'Erratum 6b, or one that ignores it): $config',
                code: code);
        }
      }

      final negotiated = _readConfig(outPtr);
      if (negotiated.maxFrameBytes <= 0) {
        // A backend that negotiates the ceiling away is broken; refusing here
        // is cheaper than discovering it one undeliverable keyframe at a time.
        lib._lib.lookupFunction<_SessionVoidNative, _SessionVoidDart>(
            'cleona_video_close')(session);
        throw VideoPipelineException(
            'backend negotiated maxFrameBytes to ${negotiated.maxFrameBytes}');
      }
      return VideoOpenAccepted(VideoPipeline._(lib, session, negotiated));
    } finally {
      calloc.free(inPtr);
      calloc.free(outPtr);
    }
  }

  void _ensureOpen() {
    if (_closed) throw VideoPipelineException('session is closed');
  }

  /// Pushes a new configuration into a live session — Erratum 1.
  ///
  /// `maxFrameBytes` follows the available bandwidth and is therefore not a
  /// property that can be fixed at [open]. When the bandwidth estimate moves,
  /// recompute the ceiling and call this. It covers both granularities: a pure
  /// rate change (bitrate and/or fps) and a resolution step.
  ///
  /// The caller **must** branch on the result — see [VideoReconfigureOutcome].
  /// [VideoRateUnachievable] is not a logging matter: it means video has to be
  /// switched off *and the user told why*, locally and at the peer. Silently
  /// carrying on produces the black picture with no explanation that this whole
  /// path exists to remove.
  ///
  /// Takes effect from the next frame. A change of width or height forces a
  /// keyframe. On any failure the session is untouched and still running.
  /// Counters are not reset. Throws [VideoPipelineException] for caller bugs
  /// (invalid arguments, closed session) — those are not link conditions.
  VideoReconfigureOutcome reconfigure(VideoConfig config) {
    _ensureOpen();
    _validate(config);

    final f = _lib._lib
        .lookupFunction<_ReconfigureNative, _ReconfigureDart>('cleona_video_reconfigure');

    final inPtr = calloc<_NativeConfig>();
    final outPtr = calloc<_NativeConfig>();
    try {
      _writeConfig(inPtr, config);
      final rc = f(_session, inPtr, outPtr);

      switch (rc) {
        case _kOk:
          _negotiated = _readConfig(outPtr);
          // The ceiling may have gone up as well as down; the read buffer is
          // sized from it and has to keep up, or the next large keyframe would
          // come back as ERR_BUFFER_TOO_SMALL.
          if (_negotiated.maxFrameBytes > _readBufCap) {
            _growReadBuffer(_negotiated.maxFrameBytes);
          }
          return VideoReconfigureAccepted(_negotiated);
        case _kErrRateUnachievable:
          return VideoRateUnachievable(
            requested: config,
            stillRunningWith: _negotiated,
          );
        case _kErrInvalid:
          throw VideoPipelineException(
              'backend rejected the reconfigure arguments: $config', code: rc);
        case _kErrState:
          throw VideoPipelineException('reconfigure on a closed session',
              code: rc);
        default:
          throw VideoPipelineException('reconfigure failed', code: rc);
      }
    } finally {
      calloc.free(inPtr);
      calloc.free(outPtr);
    }
  }

  /// Starts capture, encoder and decoder.
  void start() {
    _ensureOpen();
    final f = _lib._lib
        .lookupFunction<_SessionInt32Native, _SessionInt32Dart>('cleona_video_start');
    final rc = f(_session);
    if (rc != _kOk) {
      throw VideoPipelineException('start failed', code: rc);
    }
    _running = true;
  }

  /// Stops capture, encoder and decoder. Idempotent. The session can be
  /// started again; the decoder will then require a keyframe again.
  void stop() {
    if (_closed) return;
    _lib._lib.lookupFunction<_SessionVoidNative, _SessionVoidDart>(
        'cleona_video_stop')(_session);
    _running = false;
  }

  /// Whether [start] has been called and [stop] has not.
  bool get isRunning => _running;

  /// Reads one encoded frame, or null on timeout.
  ///
  /// Returns null both when nothing was produced within [timeoutMs] and when
  /// own video is switched off — those are the same thing to a caller, and
  /// neither is an error.
  ///
  /// Throws [VideoPipelineException] when the session is not running.
  ///
  /// The read buffer is sized at `negotiated.maxFrameBytes`, so the
  /// buffer-too-small path is unreachable in normal operation; it is handled
  /// anyway, by growing once and retrying, because a silent frame loss here
  /// would be invisible in the report.
  EncodedVideoFrame? readEncoded({int timeoutMs = 100}) {
    _ensureOpen();
    final f = _lib._lib.lookupFunction<_ReadNative, _ReadDart>('cleona_video_read_encoded');

    for (var attempt = 0; attempt < 2; attempt++) {
      final rc = f(_session, _readBuf, _readBufCap, _outSize, _outFlags,
          _outPts, timeoutMs);
      switch (rc) {
        case _kReadFrame:
          final size = _outSize.value;
          return EncodedVideoFrame(
            // Copy out: the native buffer is reused on the next read.
            data: Uint8List.fromList(_readBuf.asTypedList(size)),
            flags: _outFlags.value,
            ptsUs: _outPts.value,
          );
        case _kReadTimeout:
          return null;
        case _kErrBufferTooSmall:
          // The frame stays pending natively, so growing and retrying loses
          // nothing.
          _growReadBuffer(_outSize.value);
          continue;
        case _kErrState:
          throw VideoPipelineException('read on a session that is not running',
              code: rc);
        default:
          throw VideoPipelineException('read failed', code: rc);
      }
    }
    throw VideoPipelineException(
        'read still reported a too-small buffer after growing to $_readBufCap');
  }

  void _growReadBuffer(int required) {
    calloc.free(_readBuf);
    _readBufCap = required;
    _readBuf = calloc<Uint8>(_readBufCap);
  }

  /// Hands a peer's frame to the decoder, which renders it into its own
  /// texture. No pixels come back (I10).
  ///
  /// [isKeyframe] is what the peer reported. It must match the bitstream; a
  /// backend that detects a contradiction returns
  /// [VideoSubmitResult.decodeError] rather than feeding its decoder a lie.
  VideoSubmitResult submitEncoded(Uint8List data, {required bool isKeyframe}) {
    _ensureOpen();
    if (data.isEmpty) {
      throw VideoPipelineException('submitEncoded called with an empty frame');
    }
    final f =
        _lib._lib.lookupFunction<_SubmitNative, _SubmitDart>('cleona_video_submit_encoded');

    if (_submitBuf == null || _submitBufCap < data.length) {
      if (_submitBuf != null) calloc.free(_submitBuf!);
      _submitBufCap = data.length;
      _submitBuf = calloc<Uint8>(_submitBufCap);
    }
    _submitBuf!.asTypedList(data.length).setAll(0, data);

    final rc = f(_session, _submitBuf!, data.length,
        isKeyframe ? kVideoFlagKeyframe : 0);
    switch (rc) {
      case _kSubmitAccepted:
        return VideoSubmitResult.accepted;
      case _kSubmitAwaitingKeyframe:
        return VideoSubmitResult.awaitingKeyframe;
      case _kErrDecode:
        return VideoSubmitResult.decodeError;
      case _kErrState:
        throw VideoPipelineException(
            'submit on a session that is not running', code: rc);
      case _kErrInvalid:
        throw VideoPipelineException('submit rejected the arguments', code: rc);
      default:
        throw VideoPipelineException('submit failed', code: rc);
    }
  }

  /// The renderer texture id for a Flutter `Texture` widget, or null when this
  /// backend has no texture path.
  ///
  /// Deliberately an `int?` and not a `dart:ui` type — see the library doc.
  /// Valid between [start] and [stop]; re-query after every [start].
  int? get textureId {
    _ensureOpen();
    final f = _lib._lib
        .lookupFunction<_TextureNative, _TextureDart>('cleona_video_get_texture_id');
    final rc = f(_session, _outTexture);
    if (rc == _kOk) return _outTexture.value;
    if (rc == _kErrUnsupported) return null;
    if (rc == _kErrState) return null;
    throw VideoPipelineException('get_texture_id failed', code: rc);
  }

  /// Asks the encoder for a keyframe as soon as possible. Idempotent.
  ///
  /// Returns false when the backend has no forced-keyframe control. Throws on
  /// a real error.
  bool requestKeyframe() {
    _ensureOpen();
    final f = _lib._lib.lookupFunction<_SessionInt32Native, _SessionInt32Dart>(
        'cleona_video_request_keyframe');
    final rc = f(_session);
    if (rc == _kOk) return true;
    if (rc == _kErrUnsupported) return false;
    throw VideoPipelineException('request_keyframe failed', code: rc);
  }

  /// Switches **our own** video on or off.
  ///
  /// I12: this is the only video mute. There is no counterpart that stops the
  /// peer from sending, and none may be added. The state change is what
  /// `CALL_MEDIA_STATE` carries on the wire (V1.12) — one flag, "I am sending
  /// video" — so the peer shows "video off" rather than a frozen frame.
  ///
  /// Switching capture back on produces a keyframe unconditionally: the peer's
  /// decoder has been starved and any delta frame would be undecodable there.
  set captureEnabled(bool on) {
    _ensureOpen();
    _lib._lib.lookupFunction<_SetEnabledNative, _SetEnabledDart>(
        'cleona_video_set_capture_enabled')(_session, on ? 1 : 0);
  }

  /// Switches to the next camera. Returns false when the device has only one.
  ///
  /// The negotiated format is unchanged, so nothing has to be renegotiated.
  bool switchCamera() {
    _ensureOpen();
    final f = _lib._lib.lookupFunction<_SessionInt32Native, _SessionInt32Dart>(
        'cleona_video_switch_camera');
    final rc = f(_session);
    if (rc == _kOk) return true;
    if (rc == _kErrUnsupported) return false;
    if (rc == _kErrBackend) {
      throw VideoPipelineException('camera switch failed in the backend',
          code: rc);
    }
    throw VideoPipelineException('switch_camera failed', code: rc);
  }

  /// The verification report (I11). Valid in every state after open.
  VideoReport report() {
    _ensureOpen();
    _lib._lib.lookupFunction<_ReportNative, _ReportDart>(
        'cleona_video_get_report')(_session, _reportPtr);
    final r = _reportPtr.ref;
    return VideoReport(
      codecInUse: r.codecInUse,
      hardwareEncode: r.hardwareEncode,
      hardwareDecode: r.hardwareDecode,
      negotiatedWidth: r.negotiatedWidth,
      negotiatedHeight: r.negotiatedHeight,
      negotiatedFps: r.negotiatedFps,
      captureBackend: r.captureBackend,
      encodeBackend: r.encodeBackend,
      framesCaptured: r.framesCaptured,
      framesEncoded: r.framesEncoded,
      framesDroppedOversize: r.framesDroppedOversize,
      framesDecoded: r.framesDecoded,
      decodeFailures: r.decodeFailures,
    );
  }

  /// Releases the session and every native buffer. Idempotent.
  void close() {
    if (_closed) return;
    _closed = true;
    _running = false;
    _lib._lib.lookupFunction<_SessionVoidNative, _SessionVoidDart>(
        'cleona_video_close')(_session);
    _session = nullptr;

    calloc.free(_readBuf);
    calloc.free(_outSize);
    calloc.free(_outFlags);
    calloc.free(_outPts);
    calloc.free(_outTexture);
    calloc.free(_reportPtr);
    if (_submitBuf != null) {
      calloc.free(_submitBuf!);
      _submitBuf = null;
    }
  }
}
