/// Opus codec layer between [VoiceSession] and the call send/receive path.
///
/// Takes the [VoiceFormat] reported by [VoiceSession.format] (I3, I4) and
/// creates an [OpusFFI] encoder/decoder at exactly that rate. Never chooses
/// a rate — the platform chose it, this layer adapts to it.
///
/// ## Work package
///
/// V1.9 (SPEC_VOICE_VIDEO_REWORK.md). Depends on V0.2 (mock) and V1.8
/// (Opus build).
///
/// ## Threading
///
/// [encode] runs in the capture isolate; [decode], [decodePlc] and
/// [decodeFec] run in the playback path (main isolate or jitter-buffer
/// isolate). The underlying [OpusFFI] is not thread-safe — create one
/// [VoiceCodec] per isolate if both directions run concurrently.
library;

import 'dart:typed_data';

import 'package:cleona/core/calls/opus_ffi.dart';
import 'package:cleona/core/calls/voice_report.dart';

/// Statistics collected by [VoiceCodec] over the lifetime of one call.
class VoiceCodecStats {
  int encodedPackets = 0;
  int decodedPackets = 0;
  int plcFrames = 0;
  int fecRecoveries = 0;

  int _totalEncodedBytes = 0;

  /// Running average of encoded Opus packet size in bytes.
  double get avgPacketSizeBytes =>
      encodedPackets == 0 ? 0.0 : _totalEncodedBytes / encodedPackets;

  /// Returns a snapshot as a map (for logging / diagnostics).
  Map<String, dynamic> toMap() => {
        'encodedPackets': encodedPackets,
        'decodedPackets': decodedPackets,
        'plcFrames': plcFrames,
        'fecRecoveries': fecRecoveries,
        'avgPacketSizeBytes': avgPacketSizeBytes,
      };

  @override
  String toString() =>
      'VoiceCodecStats(enc=$encodedPackets, dec=$decodedPackets, '
      'plc=$plcFrames, fec=$fecRecoveries, '
      'avgPkt=${avgPacketSizeBytes.toStringAsFixed(1)}B)';
}

/// Opus codec layer. One instance per call direction.
///
/// Create with [VoiceCodec.fromFormat] and dispose when the call ends.
class VoiceCodec {
  VoiceCodec._(this._opus, this.sampleRate, this.frameSamples);

  /// Creates a codec from a [VoiceFormat] reported by the platform.
  ///
  /// The [format] must have been obtained from [VoiceSession.format] — this
  /// constructor does not validate the rate beyond what [OpusFFI.withFormat]
  /// checks, because the platform is the authority (I3).
  factory VoiceCodec.fromFormat(VoiceFormat format) {
    final opus = OpusFFI.withFormat(
      sampleRate: format.sampleRate,
      frameSamples: format.frameSamples,
    );
    return VoiceCodec._(opus, format.sampleRate, format.frameSamples);
  }

  final OpusFFI _opus;

  /// The sample rate this codec operates at (from the platform).
  final int sampleRate;

  /// Samples per 20 ms frame (from the platform).
  final int frameSamples;

  /// Number of PCM bytes per frame (frameSamples * 2 for 16-bit mono).
  int get frameBytes => frameSamples * 2;

  /// Accumulated statistics. Read-only snapshot via [stats].
  final VoiceCodecStats _stats = VoiceCodecStats();

  /// Returns the current statistics snapshot.
  VoiceCodecStats get stats => _stats;

  bool _disposed = false;

  /// Whether this codec has been disposed.
  bool get isDisposed => _disposed;

  void _requireAlive(String op) {
    if (_disposed) {
      throw OpusNotAvailableException('VoiceCodec disposed (in $op)');
    }
  }

  /// Encodes one PCM-16 frame to an Opus packet.
  ///
  /// [pcm16] must be exactly [frameBytes] long (= [frameSamples] * 2 bytes
  /// of 16-bit little-endian mono PCM).
  Uint8List encode(Uint8List pcm16) {
    _requireAlive('encode');
    final result = _opus.encode(pcm16);
    _stats.encodedPackets++;
    _stats._totalEncodedBytes += result.length;
    return result;
  }

  /// Decodes one Opus packet to PCM-16.
  ///
  /// Returns exactly [frameBytes] bytes.
  Uint8List decode(Uint8List opusData) {
    _requireAlive('decode');
    final result = _opus.decode(opusData);
    _stats.decodedPackets++;
    return result;
  }

  /// Packet Loss Concealment: generates a replacement frame for a lost
  /// packet using Opus's built-in interpolation.
  ///
  /// Returns exactly [frameBytes] bytes.
  Uint8List decodePlc() {
    _requireAlive('decodePlc');
    final result = _opus.decodePlc();
    _stats.plcFrames++;
    return result;
  }

  /// FEC recovery: decodes the forward error correction data embedded in
  /// [nextPacket] to recover the *previous* lost frame.
  ///
  /// Call sequence for a gap at frame N:
  /// 1. When frame N is missing and frame N+1 arrives, call
  ///    `decodeFec(frameN1)` to recover frame N.
  /// 2. Then call `decode(frameN1)` normally for frame N+1.
  ///
  /// Returns exactly [frameBytes] bytes.
  Uint8List decodeFec(Uint8List nextPacket) {
    _requireAlive('decodeFec');
    final result = _opus.decode(nextPacket, decodeFec: true);
    _stats.fecRecoveries++;
    return result;
  }

  /// Releases the underlying Opus encoder and decoder.
  ///
  /// After dispose, all encode/decode methods throw.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _opus.dispose();
  }
}
