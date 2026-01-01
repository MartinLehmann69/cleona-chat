import 'dart:typed_data';

import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/peer_info.dart' show bytesToHex, hexToBytes;
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;

/// Screen share quality presets (Architecture §10.5.4).
///
/// Each preset maps to a [VideoConfig] pushed into the active VideoPipeline
/// via `reconfigure()`. The pipeline's hardware H.264 encoder scales the
/// capture to fit.
class ScreenSharePreset {
  final int width;
  final int height;
  final int fps;
  final int bitrateKbps;
  final String label;

  const ScreenSharePreset(
      this.width, this.height, this.fps, this.bitrateKbps, this.label);

  /// >2 Mbps: 1080p@15 fps
  static const high = ScreenSharePreset(1920, 1080, 15, 2500, '1080p');

  /// 1–2 Mbps: 720p@10 fps
  static const medium = ScreenSharePreset(1280, 720, 10, 1500, '720p');

  /// 500K–1M: 540p@5 fps
  static const low = ScreenSharePreset(960, 540, 5, 800, '540p');

  /// <500K: 360p@3 fps
  static const minimal = ScreenSharePreset(640, 360, 3, 400, '360p');

  /// Text-optimized: crisp 1080p at 2 fps — maximum sharpness for code,
  /// documents and slides at minimal bandwidth.
  static const textOptimized =
      ScreenSharePreset(1920, 1080, 2, 1000, 'Text');
}

/// Manages screen sharing state, signaling and pipeline integration
/// (Architecture §10.5.4).
///
/// Screen sharing reuses the video pipeline (H.264, §10.6): when the local
/// user starts sharing, the active VideoPipeline is reconfigured with a
/// [ScreenSharePreset] (lower FPS, potentially higher resolution for text).
/// The encoded frames travel over the same transport as camera video — no
/// separate message type, no separate encryption.
///
/// The signaling layer ([ScreenShareControl]) tells participants that the
/// video they receive is now a screen rather than a camera, so the UI can
/// adjust (full-screen layout, text-optimised rendering).
///
/// Platform capture sources (native ABI extension, not yet in cleona_video.h):
/// - Linux: PipeWire / XDG Desktop Portal (org.freedesktop.portal.ScreenCast)
/// - Android: MediaProjection API
/// - Windows: Windows.Graphics.Capture
/// - iOS/macOS: ReplayKit
class ScreenShareManager {
  final String ownUserIdHex;
  final String profileDir;
  final CLogger _log;

  bool isSharing = false;
  String? activeSharerHex;
  String? activeSharerName;

  ScreenSharePreset currentPreset = ScreenSharePreset.high;
  bool optimizeForText = false;

  void Function(proto.MessageTypeV3 type, Uint8List payload)? onSendToAll;
  void Function()? onShareStateChanged;

  /// Called when screen share starts, stops, or the quality preset changes.
  /// The caller (typically the collaboration wiring in [GroupCallManager])
  /// uses this to push a new VideoConfig into the active VideoPipeline.
  /// `null` means sharing stopped — restore camera defaults.
  void Function(ScreenSharePreset? preset)? onReconfigurePipeline;

  ScreenShareManager({
    required this.ownUserIdHex,
    required this.profileDir,
  }) : _log = CLogger.get('screen-share', profileDir: profileDir);

  void startSharing({bool textOptimized = false}) {
    if (activeSharerHex != null && activeSharerHex != ownUserIdHex) {
      _log.warn('Someone else is already sharing');
      return;
    }

    isSharing = true;
    optimizeForText = textOptimized;
    activeSharerHex = ownUserIdHex;
    currentPreset = textOptimized
        ? ScreenSharePreset.textOptimized
        : ScreenSharePreset.high;

    final control = proto.ScreenShareControl()
      ..isSharing = true
      ..width = currentPreset.width
      ..height = currentPreset.height
      ..fps = currentPreset.fps
      ..optimizeForText = optimizeForText
      ..sharerId = hexToBytes(ownUserIdHex);

    onSendToAll?.call(
      proto.MessageTypeV3.MTV3_SCREEN_SHARE_FRAME,
      control.writeToBuffer(),
    );

    onReconfigurePipeline?.call(currentPreset);
    onShareStateChanged?.call();
    _log.info('Screen share started: ${currentPreset.label} '
        '(${currentPreset.width}x${currentPreset.height}@${currentPreset.fps})');
  }

  void stopSharing() {
    if (!isSharing) return;

    isSharing = false;
    activeSharerHex = null;
    activeSharerName = null;

    final control = proto.ScreenShareControl()
      ..isSharing = false
      ..sharerId = hexToBytes(ownUserIdHex);

    onSendToAll?.call(
      proto.MessageTypeV3.MTV3_SCREEN_SHARE_FRAME,
      control.writeToBuffer(),
    );

    onReconfigurePipeline?.call(null);
    onShareStateChanged?.call();
    _log.info('Screen share stopped');
  }

  void adjustQuality(int bandwidthBps) {
    if (!isSharing) return;

    final ScreenSharePreset newPreset;
    if (optimizeForText) {
      newPreset = ScreenSharePreset.textOptimized;
    } else if (bandwidthBps > 2000000) {
      newPreset = ScreenSharePreset.high;
    } else if (bandwidthBps > 1000000) {
      newPreset = ScreenSharePreset.medium;
    } else if (bandwidthBps > 500000) {
      newPreset = ScreenSharePreset.low;
    } else {
      newPreset = ScreenSharePreset.minimal;
    }

    if (newPreset.width != currentPreset.width ||
        newPreset.fps != currentPreset.fps) {
      currentPreset = newPreset;
      onReconfigurePipeline?.call(newPreset);
      _log.info('Screen share quality adjusted: ${newPreset.label}');
    }
  }

  void handleRemoteControl(proto.ScreenShareControl control) {
    final sharerHex = bytesToHex(Uint8List.fromList(control.sharerId));
    if (sharerHex == ownUserIdHex) return;

    if (control.isSharing) {
      activeSharerHex = sharerHex;
      _log.info(
          'Remote screen share started: ${sharerHex.substring(0, 8)}');
    } else {
      if (activeSharerHex == sharerHex) {
        activeSharerHex = null;
        activeSharerName = null;
      }
      _log.info(
          'Remote screen share stopped: ${sharerHex.substring(0, 8)}');
    }

    onShareStateChanged?.call();
  }

  bool get hasActiveShare => activeSharerHex != null;
  bool get isOwnShare => activeSharerHex == ownUserIdHex;

  void dispose() {
    if (isSharing) stopSharing();
    activeSharerHex = null;
    activeSharerName = null;
  }
}
