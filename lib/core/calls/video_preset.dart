/// Video resolution and quality presets.
///
/// Separated from video_engine.dart to avoid dart:ui dependency
/// in non-Flutter contexts (CLI tools, smoke tests).
library;

/// Default video resolution presets.
class VideoPreset {
  final int width;
  final int height;
  final int bitrateKbps;
  final int fps;
  final String label;

  const VideoPreset(this.width, this.height, this.bitrateKbps, this.fps, this.label);

  /// Tile resolution for group calls — the lowest rung.
  ///
  /// ── WHY THIS RUNG EXISTS (S368) ────────────────────────────
  ///
  /// Until S368, [low] with 300 kbit/s was the lower limit. Computed
  /// against real connection rates (S368 proposal §3.4), video in groups
  /// is thereby **not forwardable at all** for a considerable part of
  /// connections: with half of its upload and K = 4 streams passed
  /// through, VDSL 50 at 500 kbit/s per stream still carries two
  /// children, DSL 16 and weak cellular **none**. With 150 kbit/s these
  /// become eight and two respectively — the difference between "does not
  /// work" and "works".
  ///
  /// ── WHY 192x144 AND NOT 320x240 WITH LESS BITRATE ───────────
  ///
  /// A tile in a group grid is not 320 px wide on any screen. Squeezing
  /// 300 kbit/s onto 240p produces block artefacts in an image that is
  /// displayed scaled down anyway; lowering the resolution as well is
  /// the cheaper half at this point. Both edge lengths are divisible by
  /// 16 — hardware encoders (§10.6) like that.
  ///
  /// **No second ladder.** This rung hangs in the same ladder as the
  /// four others ([kVideoRateLadder] in `video_rate_control.dart`);
  /// a parallel tile taxonomy would be exactly the error the library
  /// documentation there explicitly warns against.
  static const tile = VideoPreset(192, 144, 150, 15, '144p');

  static const low = VideoPreset(320, 240, 300, 15, '240p');
  static const medium = VideoPreset(640, 480, 800, 30, '480p');
  static const high = VideoPreset(1280, 720, 1500, 30, '720p');
  static const full = VideoPreset(1920, 1080, 2500, 30, '1080p');
}
