import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

// App-level fragmentation for UDP payloads > 1200 bytes.
//
// V3.1.7: NACK-based retry for reliable fragment delivery.
// Sender caches fragments, receiver sends NACK for missing ones.
//
// Header: [4B magic "CFRA"][2B fragmentId][1B index][1B total]
// NACK:   [4B magic "CFNK"][2B fragmentId][1B count][1B missing0][1B missing1]...
//
// Only what's needed per transfer type:
// - Single packet (<= 1200B): no fragmentation, no NACK
// - Fragmented (> 1200B): fragment + NACK retry
// - TLS: no fragmentation needed (TCP handles reliability)

/// Magic bytes to identify a fragmented UDP packet: "CFRA" (Cleona Fragment)
const List<int> fragmentMagic = [0x43, 0x46, 0x52, 0x41];

/// Magic bytes for fragment NACK: "CFNK" (Cleona Fragment NACK)
const List<int> fragmentNackMagic = [0x43, 0x46, 0x4E, 0x4B];

/// Maximum fragment payload size (excluding header).
/// 1200 bytes total - 4 bytes magic - 4 bytes header = 1192 bytes payload.
const int maxFragmentPayloadSize = 1192;

/// Total fragment packet size (magic + header + payload).
const int maxFragmentPacketSize = 1200;

/// Fragment header size: 4 bytes magic + 2 bytes fragmentId + 1 byte index + 1 byte total.
const int fragmentHeaderSize = 8;

class UdpFragmenter {
  /// Fragment a payload into chunks suitable for UDP.
  ///
  /// Returns a list of raw packets (each <= 1200 bytes).
  /// If the payload fits in a single packet, returns it unchanged (no fragmentation).
  static List<Uint8List> fragment(Uint8List payload, {int? fragmentId}) {
    if (payload.length <= maxFragmentPacketSize) {
      return [payload]; // Fits in one UDP packet — no fragmentation needed
    }

    final totalFragments = (payload.length / maxFragmentPayloadSize).ceil();
    if (totalFragments > 255) {
      throw ArgumentError('Payload too large for fragmentation: '
          '${payload.length} bytes = $totalFragments fragments (max 255)');
    }

    // Generate fragment ID (unique per message)
    final fid = fragmentId ?? _nextFragmentId();

    final fragments = <Uint8List>[];
    for (var i = 0; i < totalFragments; i++) {
      final start = i * maxFragmentPayloadSize;
      final end = start + maxFragmentPayloadSize;
      final chunk = payload.sublist(start, end > payload.length ? payload.length : end);

      final packet = Uint8List(fragmentHeaderSize + chunk.length);
      // Magic: CFRA
      packet[0] = fragmentMagic[0];
      packet[1] = fragmentMagic[1];
      packet[2] = fragmentMagic[2];
      packet[3] = fragmentMagic[3];
      // Fragment ID (2 bytes, big-endian)
      packet[4] = (fid >> 8) & 0xFF;
      packet[5] = fid & 0xFF;
      // Index (0-based)
      packet[6] = i;
      // Total fragments
      packet[7] = totalFragments;
      // Payload
      packet.setRange(fragmentHeaderSize, fragmentHeaderSize + chunk.length, chunk);

      fragments.add(packet);
    }

    return fragments;
  }

  /// Check if a raw UDP packet is a fragment.
  static bool isFragment(Uint8List data) {
    return data.length >= fragmentHeaderSize &&
        data[0] == fragmentMagic[0] &&
        data[1] == fragmentMagic[1] &&
        data[2] == fragmentMagic[2] &&
        data[3] == fragmentMagic[3];
  }

  /// Check if a raw UDP packet is a fragment NACK.
  static bool isFragmentNack(Uint8List data) {
    return data.length >= 7 && // magic(4) + fragmentId(2) + count(1)
        data[0] == fragmentNackMagic[0] &&
        data[1] == fragmentNackMagic[1] &&
        data[2] == fragmentNackMagic[2] &&
        data[3] == fragmentNackMagic[3];
  }

  /// Build a NACK packet: [4B "CFNK"][2B fragmentId][1B count][missing indices...]
  static Uint8List buildNack(int fragmentId, List<int> missingIndices) {
    final count = missingIndices.length.clamp(0, 255);
    final packet = Uint8List(7 + count);
    packet[0] = fragmentNackMagic[0];
    packet[1] = fragmentNackMagic[1];
    packet[2] = fragmentNackMagic[2];
    packet[3] = fragmentNackMagic[3];
    packet[4] = (fragmentId >> 8) & 0xFF;
    packet[5] = fragmentId & 0xFF;
    packet[6] = count;
    for (var i = 0; i < count; i++) {
      packet[7 + i] = missingIndices[i] & 0xFF;
    }
    return packet;
  }

  /// Parse a NACK packet. Returns (fragmentId, missingIndices) or null.
  static ({int fragmentId, List<int> missing})? parseNack(Uint8List data) {
    if (!isFragmentNack(data)) return null;
    final fragmentId = (data[4] << 8) | data[5];
    final count = data[6];
    if (data.length < 7 + count) return null;
    final missing = <int>[];
    for (var i = 0; i < count; i++) {
      missing.add(data[7 + i]);
    }
    return (fragmentId: fragmentId, missing: missing);
  }

  /// Parse fragment header from a raw packet.
  static FragmentHeader? parseHeader(Uint8List data) {
    if (!isFragment(data)) return null;

    return FragmentHeader(
      fragmentId: (data[4] << 8) | data[5],
      index: data[6],
      total: data[7],
    );
  }

  /// Extract payload from a fragment packet (strip magic + header).
  static Uint8List extractPayload(Uint8List data) {
    if (data.length <= fragmentHeaderSize) return Uint8List(0);
    return Uint8List.fromList(data.sublist(fragmentHeaderSize));
  }

  /// Check if payload needs fragmentation.
  static bool needsFragmentation(int payloadLength) =>
      payloadLength > maxFragmentPacketSize;

  // Incrementing ID (wraps at 65535).
  // Random start avoids collisions between nodes behind the same NAT
  // that boot simultaneously and both send their first fragmented message
  // (e.g. Contact Request with KEM keys).
  static int _idCounter = Random().nextInt(65536);
  static int _nextFragmentId() {
    _idCounter = (_idCounter + 1) & 0xFFFF;
    return _idCounter;
  }
}

/// Parsed fragment header.
class FragmentHeader {
  final int fragmentId; // 0-65535
  final int index;      // 0-254
  final int total;      // 1-255

  FragmentHeader({
    required this.fragmentId,
    required this.index,
    required this.total,
  });

  /// Composite key for reassembly: "sourceIp:fragmentId"
  /// Port is excluded because NAT/DNAT can remap ports between fragments
  /// of the same message (observed with Fritzbox SNAT + carrier NAT).
  String reassemblyKey(String sourceIp, int sourcePort) =>
      '$sourceIp:$fragmentId';

  @override
  String toString() => 'Fragment($fragmentId: ${index + 1}/$total)';
}

/// Reassembles fragmented UDP packets.
///
/// V3.1.7: NACK-based retry — when fragments are missing after receiving the
/// last index, a timer fires and reports missing indices via onNack callback.
/// V3.1.33: Self-rescheduling NACKs (fire up to maxNacks even without new
/// fragments arriving), sourcePort update per fragment, diagnostic logging.
class FragmentReassembler {
  final Map<String, _ReassemblyBuffer> _buffers = {};

  /// Timeout for incomplete reassemblies (hard limit).
  static const Duration reassemblyTimeout = Duration(seconds: 10);

  /// Delay before sending NACK after last fragment received.
  static const Duration nackDelay = Duration(milliseconds: 500);

  /// Max NACKs per fragment group before giving up.
  static const int maxNacks = 3;

  /// Callback: (sourceIp, sourcePort, fragmentId, missingIndices)
  /// Transport wires this to send NACK packets back to the sender.
  void Function(String sourceIp, int sourcePort, int fragmentId, List<int> missing)? onNack;

  /// Optional log callback — wired by Transport to CLogger.
  void Function(String message)? onLog;

  /// Process an incoming fragment.
  ///
  /// Returns the reassembled payload when all fragments are received,
  /// or null if still waiting for more fragments.
  Uint8List? addFragment(Uint8List rawPacket, String sourceIp, int sourcePort) {
    final header = UdpFragmenter.parseHeader(rawPacket);
    if (header == null) return null;

    final key = header.reassemblyKey(sourceIp, sourcePort);
    final payload = UdpFragmenter.extractPayload(rawPacket);

    var buffer = _buffers[key];
    if (buffer == null) {
      buffer = _ReassemblyBuffer(
        fragmentId: header.fragmentId,
        total: header.total,
        sourceIp: sourceIp,
        sourcePort: sourcePort,
        createdAt: DateTime.now(),
      );
      _buffers[key] = buffer;
      onLog?.call('Fragment buffer created: key=$key total=${header.total} '
          'from $sourceIp:$sourcePort');

      // Hard timeout — cleanup even if NACKs are pending
      Timer(reassemblyTimeout, () {
        final expired = _buffers.remove(key);
        if (expired != null) {
          expired.nackTimer?.cancel();
          if (expired.fragments.length < expired.total) {
            onLog?.call('Fragment buffer EXPIRED: key=$key '
                'got=${expired.fragments.length}/${expired.total} '
                'nacks=${expired.nackCount}');
          }
        }
      });
    }

    // Always update sourcePort to the latest fragment's port.
    // NAT/DNAT can remap ports between fragments of the same message
    // (observed with Fritzbox SNAT + carrier NAT). The latest port
    // is most likely to still have an active NAT mapping for NACKs.
    buffer.sourcePort = sourcePort;

    // Store fragment (ignore duplicates)
    if (buffer.fragments.containsKey(header.index)) return null;
    buffer.fragments[header.index] = payload;

    // Check if complete
    if (buffer.fragments.length == buffer.total) {
      _buffers.remove(key);
      buffer.nackTimer?.cancel();
      onLog?.call('Fragment reassembly complete: key=$key '
          '${buffer.total} fragments');
      return _assemble(buffer);
    }

    // Debounced NACK: re-arm the timer on every fragment. Fires nackDelay
    // after the LAST received fragment (not tied to last-index or near-
    // completion). If completion arrives in time, the timer is cancelled
    // in the complete-branch above; otherwise NACK for still-missing
    // indices. Previous trigger (last-index OR total-3) missed bursts
    // where the last fragment AND several others were lost — buffer
    // expired silently. Matches architecture doc ("NACK nach 500ms").
    _scheduleNack(key, buffer);

    return null;
  }

  void _scheduleNack(String key, _ReassemblyBuffer buffer) {
    if (buffer.nackCount >= maxNacks) return;
    buffer.nackTimer?.cancel();
    buffer.nackTimer = Timer(nackDelay, () {
      final current = _buffers[key];
      if (current == null) return; // Already completed or expired
      if (current.fragments.length == current.total) return; // Completed

      final missing = <int>[];
      for (var i = 0; i < current.total; i++) {
        if (!current.fragments.containsKey(i)) {
          missing.add(i);
        }
      }
      if (missing.isNotEmpty) {
        current.nackCount++;
        onLog?.call('Fragment NACK #${current.nackCount}: key=$key '
            'missing=${missing.length}/${current.total} → '
            '${current.sourceIp}:${current.sourcePort}');
        onNack?.call(current.sourceIp, current.sourcePort, current.fragmentId, missing);
        // Self-reschedule: fire up to maxNacks even without new fragments
        // arriving. Previously NACKs only fired when addFragment() was called,
        // so if the retransmitted fragments were also lost, the remaining
        // NACK budget was never used — the buffer just expired silently.
        _scheduleNack(key, current);
      }
    });
  }

  Uint8List _assemble(_ReassemblyBuffer buffer) {
    final parts = <Uint8List>[];
    for (var i = 0; i < buffer.total; i++) {
      final frag = buffer.fragments[i];
      if (frag == null) {
        return Uint8List(0);
      }
      parts.add(frag);
    }
    final totalLen = parts.fold<int>(0, (sum, p) => sum + p.length);
    final result = Uint8List(totalLen);
    var offset = 0;
    for (final part in parts) {
      result.setRange(offset, offset + part.length, part);
      offset += part.length;
    }
    return result;
  }

  /// Number of in-progress reassemblies.
  int get pendingCount => _buffers.length;

  /// Clear all pending reassemblies.
  void clear() => _buffers.clear();
}

class _ReassemblyBuffer {
  final int fragmentId;
  final int total;
  final String sourceIp;
  /// Updated on each received fragment — always reflects the latest NAT mapping.
  int sourcePort;
  final DateTime createdAt;
  final Map<int, Uint8List> fragments = {};
  int nackCount = 0;
  Timer? nackTimer;

  _ReassemblyBuffer({
    required this.fragmentId,
    required this.total,
    required this.sourceIp,
    required this.sourcePort,
    required this.createdAt,
  });
}
