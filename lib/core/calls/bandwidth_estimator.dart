/// Adaptive bitrate controller for video calls.
///
/// Monitors RTT and packet loss to adjust video parameters:
/// - Bitrate: 300 kbps – 2500 kbps (CBR)
/// - Resolution: 240p → 480p → 720p → 1080p
/// - Framerate: 15 fps (low) or 30 fps (normal)
///
/// Degradation cascade (Architecture Section 4.2):
/// 1. Loss > 5% → request keyframe
/// 2. Loss > 10% → reduce bitrate
/// 3. Loss > 15% → reduce framerate (30→15 fps)
/// 4. Loss > 20% → reduce resolution
/// 5. Loss > 30% → pause video (audio-only fallback)
library;

import 'package:cleona/core/calls/video_preset.dart';

/// Video quality level (ordered from lowest to highest).
///
/// **Since S368 [tile] is the lowest picture level** and sits between
/// [audioOnly] and [low]. The order carries meaning: `index` IS the
/// ordering, [VideoRateController] computes ladder rungs as `index - 1`,
/// and the up/down logic below compares indices exclusively.
/// A new level therefore belongs at its place in the ordering, not at the
/// end of the enumeration.
enum VideoQuality {
  audioOnly, // video paused
  tile,      // 144p 15fps — group tile (S368)
  low,       // 240p 15fps
  medium,    // 480p 30fps
  high,      // 720p 30fps
  full,      // 1080p 30fps
}

/// Bandwidth estimation result.
class BandwidthEstimate {
  final VideoQuality quality;
  final VideoPreset preset;
  final bool needsKeyframe;
  final bool videoPaused;

  const BandwidthEstimate({
    required this.quality,
    required this.preset,
    this.needsKeyframe = false,
    this.videoPaused = false,
  });
}

/// Adaptive bitrate controller.
///
/// Feed it with packet stats (sent/received counts), and it
/// will recommend quality adjustments.
class BandwidthEstimator {
  // ── Configuration ──────────────────────────────────────────────────

  /// Loss thresholds for degradation cascade.
  static const double keyframeLossThreshold = 0.05;  // 5%
  static const double bitrateReduceThreshold = 0.10; // 10%
  static const double fpsReduceThreshold = 0.15;     // 15%
  static const double resolutionReduceThreshold = 0.20; // 20%

  /// From here on the picture falls to the tile rung (S368).
  ///
  /// Sits between [resolutionReduceThreshold] (20 % -> 240p) and
  /// [videoPauseThreshold] (30 % -> audio alone), i.e. exactly in the gap
  /// in which until S368 there was only "240p or nothing at all". 150 instead of 300
  /// kbit/s is the last step before switching off — and for
  /// group calls the only one that makes a weak connection a
  /// forwarder at all (S368 proposal §3.4).
  static const double tileReduceThreshold = 0.25;    // 25%

  static const double videoPauseThreshold = 0.30;    // 30%

  /// RTT thresholds (ms).
  static const int highRttThreshold = 300;  // Reduce quality
  static const int criticalRttThreshold = 500; // Audio-only

  /// Smoothing factor for loss rate (EMA alpha).
  static const double _emaAlpha = 0.3;

  /// Minimum time between quality changes (avoid oscillation).
  static const Duration _cooldownDuration = Duration(seconds: 3);

  /// Time of sustained good conditions before upgrading quality.
  static const Duration _upgradeDelay = Duration(seconds: 5);

  // ── State ──────────────────────────────────────────────────────────

  VideoQuality _currentQuality;
  double _smoothedLossRate = 0.0;
  int _smoothedRttMs = 0;
  DateTime _lastQualityChange = DateTime.now();
  DateTime _lastDegradation = DateTime.now();

  // Packet counters (caller resets per interval)
  int _packetsSent = 0;
  int _packetsReceived = 0;
  int _packetsLost = 0;

  /// Frames the peer's loss reports said it expected this interval
  /// ([recordLossReport]) — the denominator of the loss rate whenever a
  /// report came: the reports count Plane D frames, [recordSent] counts
  /// encoded video frames, and a fraction of one over the other would mean
  /// nothing.
  int _reportedExpected = 0;

  /// When the last round trip was measured ([updateRtt]).
  DateTime? _rttAt;

  /// How long a round-trip sample describes the line. The 1:1 call measures
  /// the round trip only with a loss report (RFC 3550 §6.4.1 inside the
  /// report, `loss_report.dart`), and reports come only in a second with
  /// loss (§17.1.1); a sample older than [_upgradeDelay] would otherwise hold
  /// a high round trip — and with it the quality cap — for the rest of the
  /// call.
  static const Duration rttLifetime = _upgradeDelay;

  BandwidthEstimator({
    VideoQuality initialQuality = VideoQuality.medium,
  }) : _currentQuality = initialQuality;

  VideoQuality get currentQuality => _currentQuality;

  double get lossRate => _smoothedLossRate;
  int get rttMs => _smoothedRttMs;

  /// Record a sent video packet.
  void recordSent() => _packetsSent++;

  /// Record a received ACK or delivery confirmation.
  void recordReceived() => _packetsReceived++;

  /// Record a lost packet (timeout or NACK).
  void recordLost() => _packetsLost++;

  /// The peer's loss report (§17.1.1, S407-GALOSS): of [expected] frames of
  /// ours, [lost] went missing there. Fed by `CallService` for the 1:1 call;
  /// until then nothing in `lib/` called [recordLost], the loss rate was
  /// always 0 and the cascade never ran (§17.5: "The target bitrate follows
  /// the measured available bandwidth and is tracked throughout the call").
  ///
  /// No report in an interval means no loss in it — the receiver reports
  /// only seconds with loss.
  void recordLossReport({required int expected, required int lost}) {
    if (expected <= 0 || lost < 0) return;
    _reportedExpected += expected;
    for (var i = 0; i < lost && i < expected; i++) {
      recordLost();
    }
  }

  /// Update RTT measurement.
  void updateRtt(int rttMs) {
    _rttAt = DateTime.now();
    if (_smoothedRttMs == 0) {
      _smoothedRttMs = rttMs;
    } else {
      _smoothedRttMs = ((_emaAlpha * rttMs) + ((1 - _emaAlpha) * _smoothedRttMs)).round();
    }
  }

  /// Evaluate current conditions and recommend quality adjustment.
  /// Call this periodically (e.g., every 1 second).
  BandwidthEstimate evaluate() {
    final now = DateTime.now();

    // Calculate current loss rate — against what the peer's reports
    // expected when one came, otherwise against what was sent.
    final totalPackets =
        _reportedExpected > 0 ? _reportedExpected : _packetsSent;
    final currentLoss = totalPackets > 0
        ? (_packetsLost / totalPackets).clamp(0.0, 1.0)
        : 0.0;

    // EMA smoothing
    _smoothedLossRate = (_emaAlpha * currentLoss) +
        ((1 - _emaAlpha) * _smoothedLossRate);

    // A round trip nobody measured again for [rttLifetime] no longer counts.
    final rttAt = _rttAt;
    if (rttAt != null && now.difference(rttAt) > rttLifetime) {
      _smoothedRttMs = 0;
      _rttAt = null;
    }

    // Reset counters for next interval
    _packetsSent = 0;
    _packetsReceived = 0;
    _packetsLost = 0;
    _reportedExpected = 0;

    // Determine target quality
    var targetQuality = _currentQuality;
    var needsKeyframe = false;

    // Degradation (fast — react immediately)
    if (_smoothedLossRate >= videoPauseThreshold ||
        _smoothedRttMs >= criticalRttThreshold) {
      targetQuality = VideoQuality.audioOnly;
    } else if (_smoothedLossRate >= tileReduceThreshold) {
      targetQuality = VideoQuality.tile;
    } else if (_smoothedLossRate >= resolutionReduceThreshold) {
      targetQuality = VideoQuality.low;
    } else if (_smoothedLossRate >= fpsReduceThreshold ||
        _smoothedRttMs >= highRttThreshold) {
      targetQuality = _limitQuality(VideoQuality.medium);
    } else if (_smoothedLossRate >= bitrateReduceThreshold) {
      targetQuality = _limitQuality(VideoQuality.medium);
    }

    // Request keyframe on moderate loss
    if (_smoothedLossRate >= keyframeLossThreshold) {
      needsKeyframe = true;
    }

    // Upgrade (slow — require sustained good conditions)
    if (_smoothedLossRate < keyframeLossThreshold &&
        _smoothedRttMs < highRttThreshold &&
        now.difference(_lastDegradation) > _upgradeDelay) {
      final nextUp = _nextHigherQuality(_currentQuality);
      if (nextUp != _currentQuality) {
        targetQuality = nextUp;
      }
    }

    // Apply cooldown
    if (targetQuality != _currentQuality) {
      if (now.difference(_lastQualityChange) < _cooldownDuration) {
        // In cooldown — only allow downgrades, not upgrades
        if (targetQuality.index > _currentQuality.index) {
          targetQuality = _currentQuality; // block upgrade during cooldown
        }
      }
      if (targetQuality != _currentQuality) {
        if (targetQuality.index < _currentQuality.index) {
          _lastDegradation = now;
        }
        _currentQuality = targetQuality;
        _lastQualityChange = now;
      }
    }

    return BandwidthEstimate(
      quality: _currentQuality,
      preset: _qualityToPreset(_currentQuality),
      needsKeyframe: needsKeyframe,
      videoPaused: _currentQuality == VideoQuality.audioOnly,
    );
  }

  /// Map quality level to video preset.
  static VideoPreset _qualityToPreset(VideoQuality q) {
    switch (q) {
      // [VideoQuality.audioOnly] gets the LOWEST rung, not the
      // second lowest: with `videoPaused == true` the caller reads
      // no preset anyway, and if it does after all, it should be the cheapest.
      case VideoQuality.audioOnly:
      case VideoQuality.tile:
        return VideoPreset.tile;
      case VideoQuality.low:
        return VideoPreset.low;
      case VideoQuality.medium:
        return VideoPreset.medium;
      case VideoQuality.high:
        return VideoPreset.high;
      case VideoQuality.full:
        return VideoPreset.full;
    }
  }

  /// Prevent upgrading past a ceiling.
  VideoQuality _limitQuality(VideoQuality ceiling) {
    if (_currentQuality.index > ceiling.index) return ceiling;
    return _currentQuality;
  }

  /// Next higher quality level.
  VideoQuality _nextHigherQuality(VideoQuality q) {
    final idx = q.index + 1;
    if (idx >= VideoQuality.values.length) return q;
    return VideoQuality.values[idx];
  }

  /// Reset estimator state (e.g., on network change).
  void reset() {
    _smoothedLossRate = 0.0;
    _smoothedRttMs = 0;
    _packetsSent = 0;
    _packetsReceived = 0;
    _packetsLost = 0;
    _reportedExpected = 0;
    _rttAt = null;
    _lastQualityChange = DateTime.now();
    _lastDegradation = DateTime.now();
  }
}
