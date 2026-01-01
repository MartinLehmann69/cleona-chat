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
///   * **The delivery ceiling for one live-media frame**
///     ([kLiveMediaMaxFrameBytes], `lib/core/calls/live_media_frame_budget.dart`)
///     — 204 parts of 1188 B of payload each (§11.2). Until S392 the value sat
///     in `lib/core/codec/udp_fragmenter.dart` and was derived from the retired
///     CFRL wire format (one-byte index, XOR parity share); that format has no
///     place in 4.2, so the constant moved to the layer that consumes it. This
///     file **consumes** it. It is never recomputed or duplicated here — see
///     [VideoRateController._ceiling].
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
///   3. [VideoRateControlShutdown] — not even the lowest rung fits under the
///      ceiling ([VideoPreset.tile] since S368; it was [VideoPreset.low]
///      before, and moving the floor down is exactly what made group video
///      reachable on weak links at all — S368 proposal §3.4)
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
import 'package:cleona/core/calls/live_media_frame_budget.dart';
import 'package:cleona/core/calls/video_pipeline.dart';
import 'package:cleona/core/calls/video_preset.dart';

/// The preset ladder this controller walks, lowest first. Deliberately the
/// same five rungs [BandwidthEstimator] already maps [VideoQuality] onto
/// (`_qualityToPreset` in `bandwidth_estimator.dart`) — a SECOND "ladder"
/// here would be the second preset taxonomy this package exists to avoid.
///
/// **Four until S368, five since S368** — and the fifth was INSERTED,
/// not placed alongside. That is exactly why this paragraph stands here:
/// it also prevented the error it describes on the next occasion.
const List<VideoPreset> kVideoRateLadder = <VideoPreset>[
  // S368: [VideoPreset.tile] is the new lowest rung, INSERTED and not
  // placed alongside. The warning one line above is the reason: a
  // separate tile ladder would be the second preset taxonomy this
  // package exists to avoid. `BandwidthEstimator._qualityToPreset`
  // maps [VideoQuality.tile] onto exactly this rung, and the index
  // computation `index - 1` carries the insertion, because the new level
  // also stands at its place in the ordering there.
  VideoPreset.tile,
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
/// call — see `BUGFIX_CURRENT.md AV-V1.17` for the exact handoff.
enum VideoRateShutdownReason {
  /// No encoder step — not even [VideoPreset.tile], the lowest rung —
  /// produces frames that fit under the delivery ceiling. Wire form:
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

  /// The ladder rung currently in force ([VideoQuality.tile] ..
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
  /// handing it back (see `_checkCeiling` and `_exceedsRequest`) and every field here may be
  /// smaller than what was asked for, never larger.
  final VideoConfig negotiated;

  /// True when the single-rung step towards the target was itself rejected
  /// by the backend and the controller fell back to the lowest rung
  /// ([VideoPreset.tile] since S368) — the
  /// last-resort attempt Abnahme criterion 3 requires before a shutdown
  /// signal is justified. False on every ordinary step.
  final bool forcedToLowest;
}

/// No encoder step fits the delivery ceiling — not even [VideoPreset.tile],
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

/// Thrown when the backend negotiates `maxFrameBytes` above the delivery
/// ceiling (I9, `cleona_video.h`) — a hard limit, not a link condition.
/// Resolution, frame rate or bitrate above the request are NOT thrown since
/// S431 (33.G14): the rung counts as not reachable and the controller stays
/// where it is (see `VideoRateController._applyRung`).
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
/// Returns null for [VideoOpenAccepted] — nothing to shut down — and for
/// [VideoOpenBelowDeviceMinimum] (Erratum 8): the device cannot go this
/// small, which is not the link; the caller opens again one rung higher
/// (owner S431 E-15, answer 16 a) and switches nothing off. The caller
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
    VideoOpenBelowDeviceMinimum() => null,
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
    /// the ceiling is always [kLiveMediaMaxFrameBytes] — the single source
    /// (see the library doc). A smoke test uses this to simulate a ceiling
    /// so small that even [VideoPreset.tile] cannot fit, which the real
    /// constant (242'352 B) never does on purpose; there is no production
    /// code path that sets it.
    int? maxFrameBytesOverrideForTests,
    this.onWarning,

    /// The lowest rung this device is known to reach, when [VideoPipeline.open]
    /// already had to go above [VideoQuality.medium] because the camera cannot
    /// go smaller (Erratum 8, owner S431 E-15 answer 16 a). Null = no floor
    /// known yet.
    VideoQuality? deviceFloorQuality,
  })  : estimator = estimator ?? BandwidthEstimator(initialQuality: initialQuality),
        _ladder = List<VideoPreset>.unmodifiable(ladder),
        _ceiling = maxFrameBytesOverrideForTests ?? kLiveMediaMaxFrameBytes,
        _appliedRung = _rungForQuality(initialQuality, ladder.length),
        _deviceFloorRung = deviceFloorQuality == null
            ? 0
            : _rungForQuality(deviceFloorQuality, ladder.length) {
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

  /// Receives a loggable line when the backend negotiates above a request
  /// (see [_applyRung]). This class has no logger of its own; the engine
  /// passes its own.
  final void Function(String message)? onWarning;

  /// Index into [_ladder] of the rung currently pushed to [pipeline].
  int _appliedRung;

  /// Rungs the backend answered above the request (ABI violation, S431
  /// 33.G14). Not tried again until [forgetUnreachableRungs] (camera switch)
  /// or the end of this controller.
  final Set<int> _unreachableRungs = <int>{};

  /// The lowest rung this device reaches: every rung below it was answered
  /// with `CLEONA_VIDEO_ERR_BELOW_DEVICE_MINIMUM` (Erratum 8), or open() had
  /// to start above it. The target rung never goes below it, so the
  /// controller does not ask for an unreachable geometry every second, and
  /// the emergency attempt goes to this rung instead of rung 0.
  int _deviceFloorRung;

  /// Another camera may reach smaller rungs than the previous one: a camera
  /// switch clears the rungs found unreachable so far (owner S431 E-14) and
  /// the device floor learned from `CLEONA_VIDEO_ERR_BELOW_DEVICE_MINIMUM`
  /// (Erratum 8).
  void forgetUnreachableRungs() {
    _unreachableRungs.clear();
    _deviceFloorRung = 0;
  }

  VideoConfig? _lastNegotiated;

  /// The delivery ceiling every [VideoConfig] this controller builds carries
  /// as `maxFrameBytes` — [kLiveMediaMaxFrameBytes] in production, consumed
  /// unchanged (never recomputed, never duplicated).
  int get ceiling => _ceiling;

  /// The ladder rung currently in force. Never
  /// [VideoQuality.audioOnly] — this controller's ladder only spans
  /// [VideoPreset.tile] through [VideoPreset.full]; an audio-only fallback for
  /// a merely-poor (not unachievable) link is signalled through
  /// [BandwidthEstimate.videoPaused] on [VideoRateControlOutcome.estimate]
  /// and is the caller's decision, same as [VideoPipeline.captureEnabled].
  VideoQuality get appliedQuality => _qualityForRung(_appliedRung);

  /// What the backend last accepted, or null before the first successful
  /// [evaluateAndApply].
  VideoConfig? get lastNegotiated => _lastNegotiated;

  /// [VideoQuality.tile] is index 1 (index 0 is [VideoQuality.audioOnly],
  /// which has no ladder rung of its own here) through [VideoQuality.full]
  /// at index 5. Ladder index is quality index minus one, clamped to the
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
    var targetRung = _rungForQuality(estimate.quality, _ladder.length);
    // Erratum 8: a rung below the device's smallest geometry is not on this
    // device's ladder; the estimate cannot ask for it.
    if (targetRung < _deviceFloorRung) targetRung = _deviceFloorRung;

    var nextRung = _appliedRung;
    if (targetRung > _appliedRung) {
      nextRung = _appliedRung + 1;
    } else if (targetRung < _appliedRung) {
      nextRung = _appliedRung - 1;
    }

    // A rung the backend already answered above the request is not tried
    // again: on such a camera every attempt would cost two encoder rebuilds.
    if (nextRung == _appliedRung || _unreachableRungs.contains(nextRung)) {
      return VideoRateControlUnchanged(estimate: estimate, quality: appliedQuality);
    }

    switch (_applyRung(nextRung)) {
      case _RungAccepted(:final negotiated):
        _appliedRung = nextRung;
        return VideoRateControlStepped(
          estimate: estimate,
          quality: appliedQuality,
          negotiated: negotiated,
        );
      case _RungAboveRequest(:final restored):
        if (restored) {
          return VideoRateControlUnchanged(estimate: estimate, quality: appliedQuality);
        }
        return _shutdown(estimate);
      case _RungBelowDeviceMinimum():
        // Erratum 8: the session is unchanged and keeps sending on the
        // applied rung; nothing is switched off.
        return VideoRateControlUnchanged(estimate: estimate, quality: appliedQuality);
      case _RungUnachievable():
        break;
    }

    // The stepped rung did not fit. Erratum E1 / Abnahme 3: silence is not an
    // option, but neither is declaring defeat without having actually tried
    // the lowest rung this device reaches. Attempt it now, bypassing the
    // one-rung-per-call limit — this is the emergency check, not a quality
    // choice. A lowest rung this device cannot reach is skipped; the applied
    // rung is still running (`CLEONA_VIDEO_ERR_RATE_UNACHIEVABLE` and
    // `CLEONA_VIDEO_ERR_BELOW_DEVICE_MINIMUM` leave the session unchanged).
    final lowest = _deviceFloorRung;
    if (nextRung != lowest) {
      if (_unreachableRungs.contains(lowest)) {
        return VideoRateControlUnchanged(estimate: estimate, quality: appliedQuality);
      }
      switch (_applyRung(lowest)) {
        case _RungAccepted(:final negotiated):
          _appliedRung = lowest;
          return VideoRateControlStepped(
            estimate: estimate,
            quality: appliedQuality,
            negotiated: negotiated,
            forcedToLowest: true,
          );
        case _RungAboveRequest(:final restored):
          if (restored) {
            return VideoRateControlUnchanged(estimate: estimate, quality: appliedQuality);
          }
        case _RungBelowDeviceMinimum():
          return VideoRateControlUnchanged(estimate: estimate, quality: appliedQuality);
        case _RungUnachievable():
          break;
      }
    }

    return _shutdown(estimate);
  }

  VideoRateControlShutdown _shutdown(BandwidthEstimate estimate) {
    return VideoRateControlShutdown(
      estimate: estimate,
      reason: VideoRateShutdownReason.bandwidthInsufficient,
      detail: 'no encoder step fits the delivery ceiling of $_ceiling B '
          '(kLiveMediaMaxFrameBytes, 204 parts x 1188 B, §11.2); '
          '${_ladder[_deviceFloorRung]} was attempted and also rejected '
          '(CLEONA_VIDEO_ERR_RATE_UNACHIEVABLE)',
    );
  }

  /// Pushes the configuration for [rung] and returns [_RungAccepted] with the
  /// negotiated result, or [_RungUnachievable] when the backend reported
  /// [VideoRateUnachievable]/`CLEONA_VIDEO_ERR_RATE_UNACHIEVABLE`.
  ///
  /// When the backend answers with a configuration ABOVE the request (S431
  /// 33.G14: the Android camera's smallest size is 320x240, the tile rung asks
  /// for 192x144), the rung is not reachable on this device: it is recorded in
  /// [_unreachableRungs], the backend is put back on the applied rung and the
  /// result is [_RungAboveRequest]. Never an exception — this runs inside the
  /// engine's once-a-second timer, and an exception there reached the crash
  /// dialog over the running call.
  _RungResult _applyRung(int rung) {
    final requested = _configFor(rung);
    final outcome = pipeline.reconfigure(requested);
    switch (outcome) {
      case VideoReconfigureAccepted(:final negotiated):
        _checkCeiling(requested, negotiated);
        if (_exceedsRequest(requested, negotiated)) {
          _unreachableRungs.add(rung);
          onWarning?.call('video rate: backend negotiated above the request, '
              'which the ABI forbids; rung ${_qualityForRung(rung)} is not '
              'reachable on this device and will not be tried again, staying on '
              '$appliedQuality (requested=$requested, negotiated=$negotiated)');
          return _RungAboveRequest(restored: _restoreAppliedRung());
        }
        _lastNegotiated = negotiated;
        return _RungAccepted(negotiated);
      case VideoReconfigureBelowDeviceMinimum():
        // Erratum 8: the backend says itself that this device cannot go this
        // small. The session is unchanged, so no restore is needed; the rung
        // above becomes the lowest one the target may name.
        final floor = rung + 1 < _ladder.length ? rung + 1 : _ladder.length - 1;
        if (floor > _deviceFloorRung) _deviceFloorRung = floor;
        onWarning?.call('video rate: rung ${_qualityForRung(rung)} lies below the '
            'smallest geometry of this device (ERR_BELOW_DEVICE_MINIMUM); lowest '
            'reachable rung is now ${_qualityForRung(_deviceFloorRung)}, staying '
            'on $appliedQuality (requested=$requested)');
        return const _RungBelowDeviceMinimum();
      case VideoRateUnachievable():
        return const _RungUnachievable();
    }
  }

  /// Puts the backend back on [_appliedRung] after a rung came back above the
  /// request, so Dart and the backend agree again. Returns false when the
  /// backend rejects the applied rung itself
  /// (`CLEONA_VIDEO_ERR_RATE_UNACHIEVABLE`).
  bool _restoreAppliedRung() {
    final requested = _configFor(_appliedRung);
    final outcome = pipeline.reconfigure(requested);
    switch (outcome) {
      case VideoReconfigureAccepted(:final negotiated):
        _checkCeiling(requested, negotiated);
        if (_exceedsRequest(requested, negotiated)) {
          onWarning?.call('video rate: backend negotiated above the request '
              'when restoring $appliedQuality '
              '(requested=$requested, negotiated=$negotiated)');
        }
        _lastNegotiated = negotiated;
        return true;
      case VideoReconfigureBelowDeviceMinimum():
        // Erratum 8 forbids switching video off for this; the session keeps
        // sending with what it has. Dart and the backend may disagree about
        // the geometry until the next accepted step.
        onWarning?.call('video rate: restoring $appliedQuality was answered '
            'ERR_BELOW_DEVICE_MINIMUM (requested=$requested)');
        return true;
      case VideoRateUnachievable():
        return false;
    }
  }

  /// Evaluates — not merely stores — [negotiated] against the delivery
  /// ceiling (I9, `cleona_video.h`). Acceptance criterion 2
  /// ("`out_negotiated` is evaluated") is this method together with
  /// [_exceedsRequest]: every field is compared, not just read into a struct
  /// nobody looks at again. I9 is a hard limit and stays an exception.
  void _checkCeiling(VideoConfig requested, VideoConfig negotiated) {
    if (negotiated.maxFrameBytes > _ceiling) {
      throw VideoRateControlException(
          'backend negotiated maxFrameBytes=${negotiated.maxFrameBytes} above '
          'the delivery ceiling of $_ceiling B — I9 violation '
          '(requested=$requested, negotiated=$negotiated)');
    }
  }

  /// True when [negotiated] is above [requested] in any field — a violation
  /// of the ABI's downward-only negotiation contract (`cleona_video.h`).
  static bool _exceedsRequest(VideoConfig requested, VideoConfig negotiated) =>
      negotiated.width > requested.width ||
      negotiated.height > requested.height ||
      negotiated.fps > requested.fps ||
      negotiated.targetBitrateKbps > requested.targetBitrateKbps;
}

/// Result of one [VideoRateController._applyRung] call.
sealed class _RungResult {
  const _RungResult();
}

/// The backend accepted the rung within the request.
final class _RungAccepted extends _RungResult {
  const _RungAccepted(this.negotiated);
  final VideoConfig negotiated;
}

/// The backend answered above the request; the rung is marked unreachable.
/// [restored] is false when the backend then rejected the applied rung.
final class _RungAboveRequest extends _RungResult {
  const _RungAboveRequest({required this.restored});
  final bool restored;
}

/// `CLEONA_VIDEO_ERR_RATE_UNACHIEVABLE`: the session is unchanged.
final class _RungUnachievable extends _RungResult {
  const _RungUnachievable();
}

/// `CLEONA_VIDEO_ERR_BELOW_DEVICE_MINIMUM` (Erratum 8): the session is
/// unchanged and the device floor has moved above the rung.
final class _RungBelowDeviceMinimum extends _RungResult {
  const _RungBelowDeviceMinimum();
}
