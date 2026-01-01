import 'dart:typed_data';

import 'package:cleona/core/calls/vpx_ffi.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;

/// Per-peer video decoder state.
class PeerVideoState {
  VpxFFI? decoder;
  int framesReceived = 0;
  int lastSeqNum = -1;
  int width = 0;
  int height = 0;

  void dispose() {
    decoder?.dispose();
    decoder = null;
  }
}

/// Receives and decodes video from multiple group call participants.
///
/// Each peer gets its own VP8 decoder instance. Incoming encrypted VP8 frames
/// are decrypted with the shared call key, decoded to I420, and delivered via
/// callback. The UI layer handles I420→RGBA conversion and display.
///
/// No dart:ui dependency — works in pure Dart context (Smoke Tests, Daemon).
class GroupVideoReceiver {
  Uint8List _callKey;
  int _callKeyVersion;
  final CLogger _log;
  final SodiumFFI _sodium = SodiumFFI();

  /// Per-peer VP8 decoders.
  final Map<String, PeerVideoState> _peers = {};

  bool _disposed = false;

  /// Callback: decoded I420 frame ready for display.
  void Function(String senderHex, Uint8List i420, int width, int height)? onDecodedI420;

  GroupVideoReceiver({
    required Uint8List callKey,
    required String profileDir,
    int callKeyVersion = 0,
  })  : _callKey = callKey,
        _callKeyVersion = callKeyVersion,
        _log = CLogger.get('group-video-rx', profileDir: profileDir);

  /// Process an incoming video frame from a peer.
  ///
  /// [senderHex]: Participant node ID (hex).
  /// [videoFrameData]: Serialized VideoFrame proto (contains encrypted VP8 data).
  void addFrame(String senderHex, Uint8List videoFrameData) {
    if (_disposed) return;

    try {
      final videoFrame = proto.VideoFrame.fromBuffer(videoFrameData);

      // Decrypt VP8 data
      final Uint8List decrypted;
      try {
        decrypted = _sodium.aesGcmDecrypt(
          Uint8List.fromList(videoFrame.encryptedData),
          _callKey,
          Uint8List.fromList(videoFrame.nonce),
        );
      } catch (_) {
        _log.debug('Video decrypt failed from ${senderHex.substring(0, 8)} seq=${videoFrame.sequenceNumber}');
        return;
      }

      // Get or create peer decoder
      final peer = _peers.putIfAbsent(senderHex, () {
        final state = PeerVideoState();
        if (VpxFFI.isAvailable()) {
          try {
            state.decoder = VpxFFI(
              width: videoFrame.width > 0 ? videoFrame.width : 640,
              height: videoFrame.height > 0 ? videoFrame.height : 480,
            );
          } catch (e) {
            _log.warn('VP8 decoder creation failed for ${senderHex.substring(0, 8)}: $e');
          }
        }
        return state;
      });

      peer.framesReceived++;
      peer.lastSeqNum = videoFrame.sequenceNumber;

      // Decode VP8 → I420
      if (peer.decoder == null) return;

      final decoded = peer.decoder!.decode(decrypted);
      if (decoded == null) return;

      peer.width = decoded.width;
      peer.height = decoded.height;

      onDecodedI420?.call(senderHex, decoded.i420Data, decoded.width, decoded.height);
    } catch (e) {
      _log.debug('Video frame processing error from ${senderHex.substring(0, 8)}: $e');
    }
  }

  /// Update the call key after key rotation.
  void updateCallKey(Uint8List newKey, int version) {
    if (version <= _callKeyVersion) return;
    _callKey = newKey;
    _callKeyVersion = version;
    _log.info('Video receiver key updated to version $version');
  }

  /// Remove a peer (left/crashed).
  void removePeer(String nodeIdHex) {
    _peers[nodeIdHex]?.dispose();
    _peers.remove(nodeIdHex);
  }

  /// Number of active video peers.
  int get activePeerCount => _peers.length;

  /// Get frames received for a specific peer.
  int framesReceivedFrom(String nodeIdHex) =>
      _peers[nodeIdHex]?.framesReceived ?? 0;

  /// Dispose all decoders.
  void dispose() {
    _disposed = true;
    for (final peer in _peers.values) {
      peer.dispose();
    }
    _peers.clear();
    _log.info('GroupVideoReceiver disposed');
  }
}
