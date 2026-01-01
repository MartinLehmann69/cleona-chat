/// Simple jitter buffer for audio frame reordering.
///
/// Buffers incoming audio frames and outputs them in correct
/// order (by sequence number).
/// Handles: out-of-order delivery, packet loss, duplicates.
///
/// Buffer depth: 100ms at 20ms frames = 5 frames.
library;

import 'dart:collection';
import 'dart:typed_data';

/// An audio frame with sequence number and data.
class AudioFrame {
  final int seqNum;
  final Uint8List data;
  final DateTime receivedAt;

  AudioFrame({required this.seqNum, required this.data})
      : receivedAt = DateTime.now();
}

/// Jitter buffer: buffers frames and outputs them in order.
class JitterBuffer {
  /// Buffer depth in frames (5 frames = 100ms at 20ms/frame).
  final int bufferDepth;

  /// Max frames in buffer (protection against memory leak).
  final int maxBufferSize;

  /// Frame duration in milliseconds.
  final int frameDurationMs;

  /// Internal buffer: seqNum → frame.
  final SplayTreeMap<int, AudioFrame> _buffer = SplayTreeMap();

  /// Next expected sequence number.
  int _nextSeqNum = -1;

  /// Statistics.
  int framesReceived = 0;
  int framesPlayed = 0;
  int framesDropped = 0;
  int framesDuplicate = 0;
  int framesLost = 0;

  JitterBuffer({
    this.bufferDepth = 5,
    this.maxBufferSize = 50,
    this.frameDurationMs = 20,
  });

  /// Insert frame into the buffer.
  void push(AudioFrame frame) {
    framesReceived++;

    // _nextSeqNum is set on the first pop() call (smallest in buffer).

    // Discard old frames (already played).
    if (_nextSeqNum >= 0 && frame.seqNum < _nextSeqNum) {
      framesDropped++;
      return;
    }

    // Discard duplicates.
    if (_buffer.containsKey(frame.seqNum)) {
      framesDuplicate++;
      return;
    }

    _buffer[frame.seqNum] = frame;

    // Buffer overflow: remove oldest frames.
    while (_buffer.length > maxBufferSize) {
      _buffer.remove(_buffer.firstKey());
      framesDropped++;
    }
  }

  /// Get the next frame for playback (or null if buffer is empty/not ready).
  ///
  /// Returns frames in sequence order.
  /// On gaps: waits until buffer depth is reached, then skips.
  AudioFrame? pop() {
    if (_buffer.isEmpty) return null;

    // Initialization: on the first pop, choose the smallest seqNum.
    if (_nextSeqNum < 0) {
      _nextSeqNum = _buffer.firstKey()!;
    }

    // Exact next frame available?
    if (_buffer.containsKey(_nextSeqNum)) {
      final frame = _buffer.remove(_nextSeqNum)!;
      _nextSeqNum++;
      framesPlayed++;
      return frame;
    }

    // Gap: wait until enough frames are buffered.
    if (_buffer.length < bufferDepth) {
      return null; // Still waiting
    }

    // Buffer full enough — count frame as lost and skip.
    while (!_buffer.containsKey(_nextSeqNum) && _buffer.isNotEmpty) {
      if (_nextSeqNum > _buffer.lastKey()!) break;
      _nextSeqNum++;
      framesLost++;
    }

    if (_buffer.containsKey(_nextSeqNum)) {
      final frame = _buffer.remove(_nextSeqNum)!;
      _nextSeqNum++;
      framesPlayed++;
      return frame;
    }

    return null;
  }

  /// Return all frames in the buffer as a sorted list (for diagnostics).
  List<int> get bufferedSeqNums => _buffer.keys.toList();

  /// Current buffer fill level.
  int get length => _buffer.length;

  /// Clear the buffer.
  void clear() {
    _buffer.clear();
    _nextSeqNum = -1;
  }

  /// Statistics as map.
  Map<String, int> get stats => {
        'received': framesReceived,
        'played': framesPlayed,
        'dropped': framesDropped,
        'duplicate': framesDuplicate,
        'lost': framesLost,
        'buffered': _buffer.length,
      };

  /// Buffer latency in milliseconds.
  int get latencyMs => _buffer.length * frameDurationMs;
}
