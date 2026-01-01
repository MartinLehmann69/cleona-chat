import 'dart:async';
import 'dart:typed_data';

import 'package:cleona/core/network/clogger.dart';

// App-level chunking for relay and Store-and-Forward paths.
//
// When an envelope exceeds RelayBudget.maxPayloadSize (300 KB), it cannot
// travel via relay or S&F. This module splits the serialized envelope into
// chunks that each fit within the budget. The receiver reassembles them
// before processing.
//
// Only used for relay/S&F paths — direct connections use UDP fragmentation
// (1200 B chunks with NACK retry) or TLS which handle large payloads natively.

/// Maximum chunk data size. Leaves headroom for RELAY_FORWARD wrapping,
/// envelope overhead, KEM header, signatures, etc.
/// 240 KB data + ~60 KB overhead = fits in 300 KB relay budget.
const int maxChunkDataSize = 240 * 1024;

/// Timeout for incomplete chunk reassembly (seconds).
const int chunkReassemblyTimeoutSec = 60;

/// Maximum number of concurrent incomplete transfers tracked.
const int maxPendingTransfers = 32;

/// Maximum chunks per transfer (240 KB * 255 = ~60 MB theoretical max).
const int maxChunksPerTransfer = 255;

/// Split serialized data into chunks suitable for relay/S&F delivery.
///
/// Returns a list of chunk data pieces. The caller wraps each into a
/// MediaChunk protobuf message with transfer_id, index, and total.
List<Uint8List> chunkPayload(Uint8List data) {
  if (data.length <= maxChunkDataSize) {
    return [data];
  }

  final totalChunks = (data.length / maxChunkDataSize).ceil();
  if (totalChunks > maxChunksPerTransfer) {
    throw ArgumentError(
      'Payload too large for relay chunking: '
      '${data.length} bytes = $totalChunks chunks (max $maxChunksPerTransfer)',
    );
  }

  final chunks = <Uint8List>[];
  for (var i = 0; i < totalChunks; i++) {
    final start = i * maxChunkDataSize;
    final end = (start + maxChunkDataSize).clamp(0, data.length);
    chunks.add(Uint8List.fromList(data.sublist(start, end)));
  }
  return chunks;
}

/// Reassembles chunks from a single transfer into the original payload.
///
/// Thread-safe: each ChunkReassembler instance tracks one transfer.
class _PendingTransfer {
  final int totalChunks;
  final Map<int, Uint8List> receivedChunks = {};
  final DateTime createdAt = DateTime.now();
  Timer? timeoutTimer;

  _PendingTransfer(this.totalChunks);

  bool get isComplete => receivedChunks.length == totalChunks;

  bool get isExpired =>
      DateTime.now().difference(createdAt).inSeconds > chunkReassemblyTimeoutSec;

  /// Add a chunk. Returns true if this was a new (non-duplicate) chunk.
  bool addChunk(int index, Uint8List data) {
    if (index >= totalChunks || index < 0) return false;
    if (receivedChunks.containsKey(index)) return false; // Dedup
    receivedChunks[index] = data;
    return true;
  }

  /// Reassemble all chunks into the original payload.
  /// Must only be called when isComplete == true.
  Uint8List reassemble() {
    // Calculate total size
    var totalSize = 0;
    for (var i = 0; i < totalChunks; i++) {
      totalSize += receivedChunks[i]!.length;
    }

    final result = Uint8List(totalSize);
    var offset = 0;
    for (var i = 0; i < totalChunks; i++) {
      final chunk = receivedChunks[i]!;
      result.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return result;
  }
}

/// Manages chunk reassembly for incoming MEDIA_CHUNK messages.
///
/// Keyed by transferIdHex. Auto-expires incomplete transfers after timeout.
class ChunkReassembler {
  final CLogger _log;
  final Map<String, _PendingTransfer> _pending = {};

  ChunkReassembler({String? profileDir})
      : _log = CLogger.get('chunk-reassembler', profileDir: profileDir);

  /// Add a chunk for a transfer.
  ///
  /// Returns the reassembled payload if all chunks are received,
  /// or null if more chunks are needed (or the chunk was rejected/duplicate).
  Uint8List? addChunk({
    required String transferIdHex,
    required int chunkIndex,
    required int totalChunks,
    required Uint8List chunkData,
  }) {
    // Validate
    if (totalChunks <= 0 || totalChunks > maxChunksPerTransfer) {
      _log.debug('Chunk rejected: invalid totalChunks=$totalChunks');
      return null;
    }
    if (chunkIndex < 0 || chunkIndex >= totalChunks) {
      _log.debug('Chunk rejected: invalid index=$chunkIndex/$totalChunks');
      return null;
    }

    // Prune expired transfers
    _pruneExpired();

    // Limit concurrent pending transfers
    if (!_pending.containsKey(transferIdHex) &&
        _pending.length >= maxPendingTransfers) {
      _log.debug('Chunk rejected: too many pending transfers (${_pending.length})');
      return null;
    }

    // Get or create transfer
    final transfer = _pending.putIfAbsent(
      transferIdHex,
      () => _PendingTransfer(totalChunks),
    );

    // Validate totalChunks matches
    if (transfer.totalChunks != totalChunks) {
      _log.debug('Chunk rejected: totalChunks mismatch '
          '(expected ${transfer.totalChunks}, got $totalChunks)');
      return null;
    }

    // Add chunk
    final isNew = transfer.addChunk(chunkIndex, chunkData);
    if (!isNew) {
      _log.debug('Chunk duplicate: transfer=$transferIdHex index=$chunkIndex');
      return null;
    }

    _log.debug('Chunk received: transfer=$transferIdHex '
        '${transfer.receivedChunks.length}/$totalChunks');

    // Check if complete
    if (transfer.isComplete) {
      _pending.remove(transferIdHex);
      final result = transfer.reassemble();
      _log.info('Chunk reassembly complete: transfer=$transferIdHex '
          'totalSize=${result.length}');
      return result;
    }

    return null;
  }

  /// Remove expired incomplete transfers.
  void _pruneExpired() {
    final expired = _pending.entries
        .where((e) => e.value.isExpired)
        .map((e) => e.key)
        .toList();
    for (final key in expired) {
      final transfer = _pending.remove(key);
      if (transfer != null) {
        _log.debug('Chunk transfer expired: $key '
            '(${transfer.receivedChunks.length}/${transfer.totalChunks} received)');
      }
    }
  }

  /// Number of currently pending (incomplete) transfers.
  int get pendingCount => _pending.length;

  /// Clean up all pending transfers.
  void dispose() {
    for (final t in _pending.values) {
      t.timeoutTimer?.cancel();
    }
    _pending.clear();
  }
}
