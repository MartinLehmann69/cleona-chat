import 'dart:typed_data';

import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/peer_info.dart' show bytesToHex, hexToBytes;
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;

/// Screen share quality presets (Architecture S10.5.4).
class ScreenSharePreset {
  final int width;
  final int height;
  final int fps;
  final String label;

  const ScreenSharePreset(this.width, this.height, this.fps, this.label);

  /// >2Mbps: 1080p@15fps
  static const high = ScreenSharePreset(1920, 1080, 15, '1080p');

  /// 1-2Mbps: 720p@10fps
  static const medium = ScreenSharePreset(1280, 720, 10, '720p');

  /// 500K-1M: 540p@5fps
  static const low = ScreenSharePreset(960, 540, 5, '540p');

  /// <500K: 360p@3fps
  static const minimal = ScreenSharePreset(640, 360, 3, '360p');

  /// Text-optimized: very crisp but 2 FPS
  static const textOptimized = ScreenSharePreset(1920, 1080, 2, 'Text');
}

/// Manages screen sharing state and control (Architecture S10.5.4).
///
/// - Linux: PipeWire / XDG Desktop Portal (org.freedesktop.portal.ScreenCast)
/// - Android: MediaProjection API
/// - Reuses video pipeline (VP8, Overlay Multicast Tree)
/// - Adaptive quality based on bandwidth
class ScreenShareManager {
  final String ownUserIdHex;
  final String profileDir;
  final CLogger _log;

  /// Whether we are currently sharing our screen.
  bool isSharing = false;

  /// Who is currently sharing (null if nobody).
  String? activeSharerHex;
  String? activeSharerName;

  /// Current share quality preset.
  ScreenSharePreset currentPreset = ScreenSharePreset.high;

  /// Whether "optimize for text" is enabled.
  bool optimizeForText = false;

  /// Callback to send control messages.
  void Function(proto.MessageTypeV3 type, Uint8List payload)? onSendToAll;

  /// UI callback when screen share state changes.
  void Function()? onShareStateChanged;

  ScreenShareManager({
    required this.ownUserIdHex,
    required this.profileDir,
  }) : _log = CLogger.get('screen-share', profileDir: profileDir);

  /// Start sharing our screen.
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

    onShareStateChanged?.call();
    _log.info('Screen share started: ${currentPreset.label}');
  }

  /// Stop sharing our screen.
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

    onShareStateChanged?.call();
    _log.info('Screen share stopped');
  }

  /// Adjust quality based on available bandwidth.
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
      _log.info('Screen share quality: ${newPreset.label}');
    }
  }

  /// Handle incoming screen share control from a remote participant.
  void handleRemoteControl(proto.ScreenShareControl control) {
    final sharerHex = bytesToHex(Uint8List.fromList(control.sharerId));
    if (sharerHex == ownUserIdHex) return; // Ignore own echo

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

  /// Check if someone is sharing their screen.
  bool get hasActiveShare => activeSharerHex != null;

  /// Check if WE are the active sharer.
  bool get isOwnShare => activeSharerHex == ownUserIdHex;

  void dispose() {
    if (isSharing) stopSharing();
    activeSharerHex = null;
    activeSharerName = null;
  }
}
