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

  static const low = VideoPreset(320, 240, 300, 15, '240p');
  static const medium = VideoPreset(640, 480, 800, 30, '480p');
  static const high = VideoPreset(1280, 720, 1500, 30, '720p');
  static const full = VideoPreset(1920, 1080, 2500, 30, '1080p');
}
