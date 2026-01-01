/// Group-call video reception on the native H.264 pipeline (§10.6).
///
/// One [VideoPipeline] per remote participant, opened with
/// [VideoDirection.decodeOnly] — the ABI's own prescription for groups
/// (`native/cleona_video/cleona_video.h`, session paragraph) plus Erratum 7,
/// which is what makes those sessions open on a machine that has a decoder but
/// no camera. Without the erratum a participant on a webcam-less desktop could
/// not SEE the others merely because it cannot BE seen.
///
/// Superseded: the VP8 path via `vpx_ffi.dart`, which decoded to I420 in Dart
/// and handed pixels up through `onDecodedI420`. Pixels no longer cross the
/// ABI in either direction (invariant I10) — what leaves this class is an
/// opaque texture id per peer, for a Flutter `Texture` widget.
///
/// Still no `dart:ui` dependency: a texture id is an `int`, so this file works
/// unchanged in the daemon and in smoke tests.
library;

import 'dart:typed_data';

import 'package:cleona/core/calls/video_pipeline.dart';
import 'package:cleona/core/calls/video_preset.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/udp_fragmenter.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;

/// Per-peer decoder state: one decode-only session and its texture.
class PeerVideoState {
  PeerVideoState({this.pipeline});

  /// The decode-only session, or null when this peer's session could not be
  /// opened (no backend, or a backend that does not implement Erratum 7).
  /// Frames from such a peer are counted and dropped — never silently
  /// reinterpreted as something else.
  VideoPipeline? pipeline;

  /// Texture id last reported for this peer, or null while there is none.
  int? textureId;

  int framesReceived = 0;
  int lastSeqNum = -1;
  int width = 0;
  int height = 0;

  /// A decoder that has not yet seen a keyframe cannot start from anything
  /// else — tracked per peer because peers key independently.
  bool hasSeenKeyframe = false;
  int consecutiveDecodeFailures = 0;

  void dispose() {
    try {
      pipeline?.stop();
      pipeline?.close();
    } catch (_) {
      // A peer leaving must not take the other sessions with it.
    }
    pipeline = null;
    textureId = null;
  }
}

/// Receives and decodes video from multiple group call participants.
///
/// Incoming frames are decrypted with the sender's own media key (§10.2.1) and
/// handed to that peer's decoder. The decoded picture never enters Dart: it is
/// rendered into the peer's texture below the ABI, and [onPeerTexture] reports
/// the id the UI needs.
class GroupVideoReceiver {
  // §10.2.1 per-sender media keys: senderUserId-hex -> their announced key.
  final Map<String, Uint8List> _peerSendKeys = {};
  final CLogger _log;
  final SodiumFFI _sodium = SodiumFFI();

  /// Per-peer decode-only sessions.
  final Map<String, PeerVideoState> _peers = {};

  bool _disposed = false;

  /// Callback: this peer's video is renderable under [textureId], or is gone
  /// again when [textureId] is null. Fires on change only.
  void Function(String senderHex, int? textureId)? onPeerTexture;

  /// Callback: this peer's decoder needs a keyframe. The caller signals the
  /// peer — asking for one is signalling, not something the video ABI does.
  void Function(String senderHex)? onKeyframeNeeded;

  GroupVideoReceiver({
    required String profileDir,
  }) : _log = CLogger.get('group-video-rx', profileDir: profileDir);

  /// Register an authenticated peer's secret media key (decrypt side, §10.2.1).
  void setPeerSendKey(String senderUserHex, Uint8List key) {
    _peerSendKeys[senderUserHex] = key;
  }

  /// Process an incoming video frame from a peer.
  ///
  /// [senderHex]: Participant node ID (hex).
  /// [videoFrameData]: Serialized VideoFrame proto (encrypted H.264 payload).
  void addFrame(String senderHex, Uint8List videoFrameData) {
    if (_disposed) return;

    try {
      final videoFrame = proto.VideoFrame.fromBuffer(videoFrameData);

      // Decrypt with the sender's own secret key (§10.2.1). A frame whose
      // sender key we have not yet learned is dropped; AES-GCM auth means a
      // frame decrypting under sender X's key genuinely came from X.
      final key = _peerSendKeys[senderHex];
      if (key == null) {
        _log.debug('Video drop: no send_key yet for ${senderHex.substring(0, 8)}');
        return;
      }
      final Uint8List decrypted;
      try {
        decrypted = _sodium.aesGcmDecrypt(
          Uint8List.fromList(videoFrame.encryptedData),
          key,
          Uint8List.fromList(videoFrame.nonce),
        );
      } catch (_) {
        _log.debug('Video decrypt failed from ${senderHex.substring(0, 8)} '
            'seq=${videoFrame.sequenceNumber}');
        return;
      }

      final peer = _peers.putIfAbsent(
          senderHex, () => _openPeer(senderHex, videoFrame));

      peer.framesReceived++;
      peer.lastSeqNum = videoFrame.sequenceNumber;
      if (videoFrame.width > 0) peer.width = videoFrame.width;
      if (videoFrame.height > 0) peer.height = videoFrame.height;

      final pipeline = peer.pipeline;
      if (pipeline == null) return;

      final isKeyframe = (videoFrame.flags & kVideoFlagKeyframe) != 0;
      if (!peer.hasSeenKeyframe && !isKeyframe) {
        onKeyframeNeeded?.call(senderHex);
        return;
      }

      final result = pipeline.submitEncoded(decrypted, isKeyframe: isKeyframe);
      switch (result) {
        case VideoSubmitResult.accepted:
          peer.hasSeenKeyframe = true;
          peer.consecutiveDecodeFailures = 0;
          _publishTexture(senderHex, peer);
        case VideoSubmitResult.awaitingKeyframe:
          onKeyframeNeeded?.call(senderHex);
        case VideoSubmitResult.decodeError:
          _registerDecodeFailure(senderHex, peer);
      }
    } catch (e) {
      _log.debug('Video frame processing error from '
          '${senderHex.substring(0, 8)}: $e');
    }
  }

  /// Opens this peer's decode-only session.
  ///
  /// Geometry comes from the first frame's announced size when it has one, and
  /// from the medium preset otherwise — the decoder and the texture are sized
  /// from it. The rate fields are required by the ABI but unused here: a
  /// decode-only session has no encoder to bound (Erratum 7).
  PeerVideoState _openPeer(String senderHex, proto.VideoFrame first) {
    final short = senderHex.substring(0, 8);
    final config = VideoConfig(
      width: first.width > 0 ? first.width : VideoPreset.medium.width,
      height: first.height > 0 ? first.height : VideoPreset.medium.height,
      fps: VideoPreset.medium.fps,
      targetBitrateKbps: VideoPreset.medium.bitrateKbps,
      maxFrameBytes: UdpFragmenter.liveMediaMaxFrameBytes,
      direction: VideoDirection.decodeOnly,
    );

    final VideoOpenOutcome outcome;
    try {
      outcome = VideoPipeline.open(config);
    } on VideoLibraryNotAvailable catch (e) {
      _log.warn('No video backend for $short — peer stays audio-only: $e');
      return PeerVideoState();
    } on VideoPipelineException catch (e) {
      // Includes a backend that does not implement Erratum 7 yet: it fails
      // closed with ERR_UNSUPPORTED rather than opening a duplex session.
      _log.warn('Decode-only session for $short failed to open: $e');
      return PeerVideoState();
    }

    switch (outcome) {
      case VideoOpenAccepted(:final pipeline):
        try {
          pipeline.start();
        } catch (e) {
          _log.warn('Decode-only session for $short failed to start: $e');
          pipeline.close();
          return PeerVideoState();
        }
        _log.info('Group video: decode-only session for $short '
            '(negotiated=${pipeline.negotiated})');
        return PeerVideoState(pipeline: pipeline);
      case VideoOpenRateUnachievable():
        // Cannot happen for a decode-only session in a correct backend — the
        // ceiling bounds an encoder that was never created. Logged rather than
        // swallowed, because it means a backend mis-implements Erratum 7.
        _log.warn('Decode-only session for $short answered '
            'RATE_UNACHIEVABLE — backend does not honour Erratum 7');
        return PeerVideoState();
    }
  }

  void _publishTexture(String senderHex, PeerVideoState peer) {
    final int? id;
    try {
      id = peer.pipeline?.textureId;
    } on VideoPipelineException catch (e) {
      _log.debug('textureId for ${senderHex.substring(0, 8)}: $e');
      return;
    }
    if (id == peer.textureId) return;
    peer.textureId = id;
    onPeerTexture?.call(senderHex, id);
  }

  void _registerDecodeFailure(String senderHex, PeerVideoState peer) {
    peer.consecutiveDecodeFailures++;
    if (peer.consecutiveDecodeFailures >= 3) {
      peer.consecutiveDecodeFailures = 0;
      peer.hasSeenKeyframe = false;
      onKeyframeNeeded?.call(senderHex);
    }
  }

  /// Remove a peer (left/crashed).
  void removePeer(String nodeIdHex) {
    final peer = _peers.remove(nodeIdHex);
    if (peer != null) {
      final hadTexture = peer.textureId != null;
      peer.dispose();
      if (hadTexture) onPeerTexture?.call(nodeIdHex, null);
    }
    _peerSendKeys.remove(nodeIdHex);
  }

  /// Number of active video peers.
  int get activePeerCount => _peers.length;

  /// Get frames received for a specific peer.
  int framesReceivedFrom(String nodeIdHex) =>
      _peers[nodeIdHex]?.framesReceived ?? 0;

  /// The renderable texture for a peer, or null when it has none (yet).
  int? textureIdFor(String nodeIdHex) => _peers[nodeIdHex]?.textureId;

  /// Dispose all sessions.
  void dispose() {
    _disposed = true;
    for (final entry in _peers.entries) {
      final hadTexture = entry.value.textureId != null;
      entry.value.dispose();
      if (hadTexture) onPeerTexture?.call(entry.key, null);
    }
    _peers.clear();
    _log.info('GroupVideoReceiver disposed');
  }
}
