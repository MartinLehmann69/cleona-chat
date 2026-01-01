/// Wires [BandwidthEstimator] to the video send path — work package V1.17
/// of `docs/SPEC_VOICE_VIDEO_REWORK.md` (Erratum E3, §13).
///
/// Work package V0.3 (`video_pipeline.dart`) opened the door
/// (`VideoPipeline.reconfigure`) but nothing walked through it:
/// `bandwidth_estimator.dart` had a finished preset ladder and, outside its
/// own file and its own smoke test, zero call sites in the repo. The old
/// `video_engine.dart:268` hard-coded `VideoPreset preset = VideoPreset.medium`
/// and never looked at the network again. §10.6 is explicit that this
/// wiring is Cleona's job — "Rate control moves to the hardware encoder;
/// Cleona's `bandwidth_estimator` only sets the target" — and that sentence
/// had no code behind it. This file is that code.
///
/// ## Division of labour (project owner decision, SPEC §7 V1.17)
///
/// Two layers, two owners, on purpose:
///
///   * **Transport** (package V1.11, `lib/core/network/udp_fragmenter.dart`)
///     owns the plain-UDP delivery ceiling for one live-media frame
///     ([UdpFragmenter.liveMediaMaxFrameBytes]) — a structural property of
///     the fragment format (one-byte index, FEC parity share), not a taste
///     value. This file **consumes** that constant. It is never recomputed
///     or duplicated here — see [VideoRateController._ceiling].
///   * **Encoder** (this file) turns a bandwidth estimate into a preset
///     recommendation and pushes it down with
///     [VideoPipeline.reconfigure], under that fixed ceiling.
///
/// ## Erratum E1 — the two and only two correct responses
///
/// A degrading link never means "stop producing frames without saying why."
/// [VideoRateController.evaluateAndApply] returns exactly one of three
/// outcomes:
///
///   1. [VideoRateControlUnchanged] — the target preset rung equals the
///      applied one; nothing to push down.
///   2. [VideoRateControlStepped] — the backend accepted a new
///      configuration, **at most one preset rung away from the previous
///      one**. A bandwidth crash walks the ladder down one rung per call
///      instead of jumping straight to the bottom, so a single lost-packet
///      burst does not collapse a 1080p call straight to 240p when 720p
///      would have done. See `_stepTowards`.
///   3. [VideoRateControlShutdown] — not even the lowest rung
///      ([VideoPreset.low]) fits under the ceiling
///      (`CLEONA_VIDEO_ERR_RATE_UNACHIEVABLE`, `cleona_video.h`). The caller
///      — `video_engine.dart` / `call_service.dart`, packages V2.3 / V2.1,
///      not this file — switches own video off and shows [reason] to the
///      user, locally and via `CALL_MEDIA_STATE` (V1.12,
///      `CallVideoOffReason.bandwidthInsufficient`). This file never calls
///      [VideoPipeline.captureEnabled] itself: I12 says only the caller that
///      owns the on/off decision may touch it, and that caller is V2.3.
///
/// `frames_dropped_oversize` staying at 0 in the field depends on every
/// caller of `cleona_video_reconfigure` doing exactly this — degrade, or
/// stop and explain, never silently discard. This file is the one caller
/// that exists today.
library;

import 'package:cleona/core/calls/bandwidth_estimator.dart';
import 'package:cleona/core/calls/video_pipeline.dart';
import 'package:cleona/core/calls/video_preset.dart';
import 'package:cleona/core/network/udp_fragmenter.dart';

/// The preset ladder this controller walks, lowest first. Deliberately the
/// same four rungs [BandwidthEstimator] already maps [VideoQuality] onto
/// (`_qualityToPreset` in `bandwidth_estimator.dart`) — a fifth "ladder" here
/// would be the second preset taxonomy this package exists to avoid.
const List<VideoPreset> kVideoRateLadder = <VideoPreset>[
  VideoPreset.low,
  VideoPreset.medium,
  VideoPreset.high,
  VideoPreset.full,
];

/// Why [VideoRateController] gave up rather than keep encoding.
///
/// One case today. Kept as an enum, not a lone bool, because it is the
/// concept `CALL_MEDIA_STATE` (V1.12) already carries as
/// `CallVideoOffReason.bandwidthInsufficient`
/// (`lib/core/service/cleona_service.dart:157-164`) — the same shortage, one
/// hop earlier. **Not** the same Dart type: `cleona_service.dart` imports
/// `lib/core/calls/call_manager.dart` and `group_call_manager.dart`, so a
/// `lib/core/calls/*.dart` file importing `cleona_service.dart` back would be
/// this repo's first calls→service→calls import cycle (checked — no file
/// under `lib/core/calls/` currently imports it). The name is deliberately
/// identical to keep the eventual mapping in `video_engine.dart` /
/// `call_service.dart` (V2.3 / V2.1) a 1:1 lookup rather than a judgement
/// call — see `BUILD_REQUEST_V1.17.md` for the exact handoff.
enum VideoRateShutdownReason {
  /// No encoder step — not even [VideoPreset.low] — produces frames that fit
  /// under the delivery ceiling. Wire form:
  /// `CallVideoOffReason.bandwidthInsufficient`.
  bandwidthInsufficient,
}

/// Outcome of [VideoRateController.evaluateAndApply].
///
/// A sealed type for the same reason [VideoReconfigureOutcome] is one
/// (`video_pipeline.dart`): "nothing changed", "degraded, still sending" and
/// "stop and explain" are three different obligations on the caller, not one
/// generic result to log and move past.
sealed class VideoRateControlOutcome {
  const VideoRateControlOutcome({required this.estimate});

  /// The [BandwidthEstimator] read that produced this outcome. Carries
  /// [BandwidthEstimate.needsKeyframe] and [BandwidthEstimate.videoPaused] —
  /// signals this file does not act on itself (keyframe requests and the
  /// audio-only fallback belong to the caller that already owns
  /// [VideoPipeline.requestKeyframe] and [VideoPipeline.captureEnabled]) but
  /// must not silently drop either.
  final BandwidthEstimate estimate;
}

/// The target preset rung equals the one already applied — no reconfigure
/// call was made.
final class VideoRateControlUnchanged extends VideoRateControlOutcome {
  const VideoRateControlUnchanged({required super.estimate, required this.quality});

  /// The ladder rung currently in force ([VideoQuality.low] ..
  /// [VideoQuality.full] — never [VideoQuality.audioOnly], see
  /// [VideoRateController.appliedQuality]).
  final VideoQuality quality;
}

/// The backend accepted a new configuration, exactly one ladder rung away
/// from the previous one (or, when the stepped rung was rejected, the lowest
/// rung reached as a last resort before giving up — see [forcedToLowest]).
final class VideoRateControlStepped extends VideoRateControlOutcome {
  const VideoRateControlStepped({
    required super.estimate,
    required this.quality,
    required this.negotiated,
    this.forcedToLowest = false,
  });

  /// The ladder rung now in force.
  final VideoQuality quality;

  /// What the backend actually negotiated — **evaluated**, not merely
  /// fetched: [VideoRateController] checks it against the request before
  /// handing it back (see `_evaluateNegotiated`) and every field here may be
  /// smaller than what was asked for, never larger.
  final VideoConfig negotiated;

  /// True when the single-rung step towards the target was itself rejected
  /// by the backend and the controller fell back to [VideoPreset.low] — the
  /// last-resort attempt Abnahme criterion 3 requires before a shutdown
  /// signal is justified. False on every ordinary step.
  final bool forcedToLowest;
}

/// No encoder step fits the delivery ceiling — not even [VideoPreset.low],
/// which was actually attempted (never assumed). The caller stops encoding
/// and tells the user [reason], instead of retrying silently.
final class VideoRateControlShutdown extends VideoRateControlOutcome {
  const VideoRateControlShutdown({
    required super.estimate,
    required this.reason,
    required this.detail,
  });

  /// Always [VideoRateShutdownReason.bandwidthInsufficient] today — see the
  /// type doc for why this stays an enum rather than a bare bool.
  final VideoRateShutdownReason reason;

  /// A short, loggable explanation. Wording and i18n for the user-facing
  /// text belong to the UI package (V1.6 / V2.3), not here — same split as
  /// [VideoRateUnachievable.reason] in `video_pipeline.dart`.
  final String detail;
}

/// Thrown when the backend violates the ABI's own negotiation contract —
/// negotiating a ceiling, resolution, frame rate or bitrate **above** what
/// was requested (`cleona_video.h`: "may be negotiated down, never up").
/// A caller bug in the backend, not a link condition — [VideoRateController]
/// fails loudly rather than caching a value nothing downstream can trust.
class VideoRateControlException implements Exception {
  VideoRateControlException(this.message);
  final String message;
  @override
  String toString() => 'VideoRateControlException: $message';
}

/// A reason to switch video off discovered at [VideoPipeline.open] time —
/// Erratum E6b (`docs/SPEC_VOICE_VIDEO_REWORK.md` §13), which gave `open()`
/// a reason instead of a bare failure a caller could not tell apart from a
/// programming error.
///
/// Deliberately **not** a [VideoRateControlOutcome]: that sealed type always
/// carries a [BandwidthEstimate] because every case of it comes out of a
/// live [VideoRateController.evaluateAndApply] tick. A failed `open()`
/// happens before any [VideoRateController] can exist — there is no
/// [VideoPipeline] yet to build one around, and no estimator has ticked —
/// so there is no estimate to attach. [videoOpenShutdownFor] is the
/// conversion function for the one case that maps cleanly onto
/// [VideoRateShutdownReason]; the other three `open()` failures
/// (`ERR_INVALID`, `ERR_UNSUPPORTED`, `ERR_BACKEND`) stay
/// [VideoPipelineException]s, exactly as `video_pipeline.dart` already models
/// them, because none of them means "the link cannot carry video" — they mean
/// "caller bug" or "no video path on this device", which V1.17 has no more
/// business relabelling at open() time than it would at reconfigure() time.
final class VideoOpenShutdown {
  const VideoOpenShutdown({required this.reason, required this.detail});

  /// Always [VideoRateShutdownReason.bandwidthInsufficient] — see
  /// [videoOpenShutdownFor].
  final VideoRateShutdownReason reason;

  /// [VideoOpenRateUnachievable.reason], carried through unchanged. Same
  /// loggable-not-user-facing convention as [VideoRateControlShutdown.detail].
  final String detail;
}

/// Maps a [VideoPipeline.open] result onto the same shutdown vocabulary
/// [VideoRateController.evaluateAndApply] uses for a failed
/// [VideoPipeline.reconfigure] call.
///
/// The mapping is 1:1, not an approximation: [VideoOpenRateUnachievable] and
/// the [VideoRateControlShutdown] this file already produces mid-call are the
/// same underlying condition — "no supported encoder step fits the delivery
/// ceiling" — discovered at two different moments (open vs. a later
/// reconfigure). Erratum E1 requires the same response either way: stop, and
/// tell the user why, instead of showing no picture or the wrong text
/// (Erratum E6b's own rationale for giving `open()` a reason at all).
///
/// Returns null for [VideoOpenAccepted] — nothing to shut down. The caller
/// (V2.3, which owns the [VideoPipeline] lifecycle and therefore calls
/// [VideoPipeline.open] itself) is expected to call this once right after
/// `open()`, before ever constructing a [VideoRateController]:
///
/// ```dart
/// switch (VideoPipeline.open(cfg)) {
///   case VideoOpenAccepted(:final pipeline):
///     final controller = VideoRateController(pipeline: pipeline);
///     pipeline.start();
///   case final other:
///     final shutdown = videoOpenShutdownFor(other)!;
///     showVideoOffReason(shutdown.reason);   // never go quiet — Erratum 1
/// }
/// ```
VideoOpenShutdown? videoOpenShutdownFor(VideoOpenOutcome outcome) {
  return switch (outcome) {
    VideoOpenAccepted() => null,
    VideoOpenRateUnachievable(:final reason) => VideoOpenShutdown(
        reason: VideoRateShutdownReason.bandwidthInsufficient,
        detail: reason,
      ),
  };
}

/// Turns a running [BandwidthEstimator] read into a
/// [VideoPipeline.reconfigure] call, one preset rung at a time.
///
/// Does not open, start, stop or close [pipeline] — the caller (V2.3) owns
/// the session lifecycle; this class only reconfigures a session that is
/// already open. Does not touch [VideoPipeline.captureEnabled] — I12 keeps
/// the on/off decision with the caller. Call [evaluateAndApply] periodically
/// (the same cadence [BandwidthEstimator.evaluate] is designed for, e.g. once
/// per second) and act on the returned [VideoRateControlOutcome].
class VideoRateController {
  VideoRateController({
    required this.pipeline,
    BandwidthEstimator? estimator,
    List<VideoPreset> ladder = kVideoRateLadder,
    VideoQuality initialQuality = VideoQuality.medium,

    /// Test-only escape hatch. Production callers must leave this null so
    /// the ceiling is always [UdpFragmenter.liveMediaMaxFrameBytes] — the
    /// single source V1.11 owns (see the library doc). A smoke test uses
    /// this to simulate a ceiling so small that even [VideoPreset.low]
    /// cannot fit, which the real constant (242'148 B) never does on
    /// purpose; there is no production code path that sets it.
    int? maxFrameBytesOverrideForTests,
  })  : estimator = estimator ?? BandwidthEstimator(initialQuality: initialQuality),
        _ladder = List<VideoPreset>.unmodifiable(ladder),
        _ceiling = maxFrameBytesOverrideForTests ?? UdpFragmenter.liveMediaMaxFrameBytes,
        _appliedRung = _rungForQuality(initialQuality, ladder.length) {
    if (_ladder.isEmpty) {
      throw ArgumentError.value(ladder, 'ladder', 'must not be empty');
    }
    if (_ceiling <= 0) {
      throw ArgumentError.value(
          _ceiling, 'maxFrameBytesOverrideForTests', 'must be > 0 (I9)');
    }
  }

  /// The session this controller reconfigures. Opened and closed by the
  /// caller.
  final VideoPipeline pipeline;

  /// Feeds this controller. Record loss/RTT on it (`recordSent`,
  /// `recordReceived`, `recordLost`, `updateRtt`) exactly as before V1.17;
  /// this class only adds what happens to the result of `evaluate()`.
  final BandwidthEstimator estimator;

  final List<VideoPreset> _ladder;
  final int _ceiling;

  /// Index into [_ladder] of the rung currently pushed to [pipeline].
  int _appliedRung;

  VideoConfig? _lastNegotiated;

  /// The delivery ceiling every [VideoConfig] this controller builds carries
  /// as `maxFrameBytes` — [UdpFragmenter.liveMediaMaxFrameBytes] in
  /// production, consumed unchanged (never recomputed, never duplicated).
  int get ceiling => _ceiling;

  /// The ladder rung currently in force. Never
  /// [VideoQuality.audioOnly] — this controller's ladder only spans
  /// [VideoPreset.low] through [VideoPreset.full]; an audio-only fallback for
  /// a merely-poor (not unachievable) link is signalled through
  /// [BandwidthEstimate.videoPaused] on [VideoRateControlOutcome.estimate]
  /// and is the caller's decision, same as [VideoPipeline.captureEnabled].
  VideoQuality get appliedQuality => _qualityForRung(_appliedRung);

  /// What the backend last accepted, or null before the first successful
  /// [evaluateAndApply].
  VideoConfig? get lastNegotiated => _lastNegotiated;

  /// [VideoQuality.low] is index 1 (index 0 is [VideoQuality.audioOnly],
  /// which has no ladder rung of its own here) through [VideoQuality.full]
  /// at index 4. Ladder index is quality index minus one, clamped to the
  /// configured ladder length.
  static int _rungForQuality(VideoQuality q, int ladderLength) {
    final idx = q.index - 1;
    if (idx < 0) return 0;
    if (idx >= ladderLength) return ladderLength - 1;
    return idx;
  }

  VideoQuality _qualityForRung(int rung) => VideoQuality.values[rung + 1];

  VideoConfig _configFor(int rung) {
    final preset = _ladder[rung];
    return VideoConfig(
      width: preset.width,
      height: preset.height,
      fps: preset.fps,
      targetBitrateKbps: preset.bitrateKbps,
      maxFrameBytes: _ceiling,
    );
  }

  /// Reads [estimator], derives a target ladder rung and pushes at most one
  /// step towards it via [VideoPipeline.reconfigure].
  ///
  /// [estimator] itself may recommend jumping several qualities at once on a
  /// sharp loss spike (`bandwidth_estimator.dart`'s existing, tested
  /// degradation cascade — unchanged by this file, see the library doc for
  /// why it stays that way). This method is what turns that recommendation
  /// into a gradual descent: never more than one ladder rung per call, so a
  /// caller ticking this once a second walks a `full`→`low` collapse over
  /// three calls, not one, and a link that recovers gets the same gradual
  /// treatment climbing back up.
  VideoRateControlOutcome evaluateAndApply() {
    final estimate = estimator.evaluate();
    final targetRung = _rungForQuality(estimate.quality, _ladder.length);

    var nextRung = _appliedRung;
    if (targetRung > _appliedRung) {
      nextRung = _appliedRung + 1;
    } else if (targetRung < _appliedRung) {
      nextRung = _appliedRung - 1;
    }

    if (nextRung == _appliedRung) {
      return VideoRateControlUnchanged(estimate: estimate, quality: appliedQuality);
    }

    final stepped = _applyRung(nextRung);
    if (stepped != null) {
      _appliedRung = nextRung;
      return VideoRateControlStepped(
        estimate: estimate,
        quality: appliedQuality,
        negotiated: stepped,
      );
    }

    // The stepped rung did not fit. Erratum E1 / Abnahme 3: silence is not an
    // option, but neither is declaring defeat without having actually tried
    // the lowest rung. Attempt it now, bypassing the one-rung-per-call limit
    // — this is the emergency check, not a quality choice.
    if (nextRung != 0) {
      final lowest = _applyRung(0);
      if (lowest != null) {
        _appliedRung = 0;
        return VideoRateControlStepped(
          estimate: estimate,
          quality: appliedQuality,
          negotiated: lowest,
          forcedToLowest: true,
        );
      }
    }

    return VideoRateControlShutdown(
      estimate: estimate,
      reason: VideoRateShutdownReason.bandwidthInsufficient,
      detail: 'no encoder step fits the delivery ceiling of $_ceiling B '
          '(V1.11 UdpFragmenter.liveMediaMaxFrameBytes); '
          '${_ladder[0]} was attempted and also rejected '
          '(CLEONA_VIDEO_ERR_RATE_UNACHIEVABLE)',
    );
  }

  /// Pushes the configuration for [rung] and returns the negotiated result,
  /// or null when the backend reported
  /// [VideoRateUnachievable]/`CLEONA_VIDEO_ERR_RATE_UNACHIEVABLE`.
  VideoConfig? _applyRung(int rung) {
    final requested = _configFor(rung);
    final outcome = pipeline.reconfigure(requested);
    switch (outcome) {
      case VideoReconfigureAccepted(:final negotiated):
        _evaluateNegotiated(requested, negotiated);
        _lastNegotiated = negotiated;
        return negotiated;
      case VideoRateUnachievable():
        return null;
    }
  }

  /// Evaluates — not merely stores — [negotiated] against [requested] and
  /// against the ABI's downward-only negotiation contract (I9,
  /// `cleona_video.h`). Abnahme criterion 2 ("`out_negotiated` wird
  /// ausgewertet") is this method: every field is compared, not just read
  /// into a struct nobody looks at again.
  void _evaluateNegotiated(VideoConfig requested, VideoConfig negotiated) {
    if (negotiated.maxFrameBytes > _ceiling) {
      throw VideoRateControlException(
          'backend negotiated maxFrameBytes=${negotiated.maxFrameBytes} above '
          'the delivery ceiling of $_ceiling B — I9 violation '
          '(requested=$requested, negotiated=$negotiated)');
    }
    if (negotiated.width > requested.width ||
        negotiated.height > requested.height ||
        negotiated.fps > requested.fps ||
        negotiated.targetBitrateKbps > requested.targetBitrateKbps) {
      throw VideoRateControlException(
          'backend negotiated above the request, which the ABI forbids '
          '(requested=$requested, negotiated=$negotiated)');
    }
  }
}
