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
//
// ── Live-Media (Architektur §10.3.1, Invariante I8, Paket V1.11) ─────────
//
// Live-Media (MTV3_CALL_AUDIO / _VIDEO / _GROUP_AUDIO / _GROUP_VIDEO) ist
// plain UDP, fire-and-forget, und ausdruecklich AUSGENOMMEN von
// Retransmission-basierter Wiederherstellung: der erste NACK-Retry feuert
// nach 500 ms ([FragmentReassembler.nackDelayInitial]), der Frame hat aber
// eine Deadline von 20-33 ms und ist dann laengst tot. Statt Retransmit
// traegt Live-Media Vorwaertsfehlerkorrektur (FEC) im Fragmentstrom selbst.
//
// Darum eigene Rahmung mit eigenem Magic "CFRL":
//
//   [4B "CFRL"][2B fragmentId][1B index][1B dataTotal][1B parityTotal]
//   [4B payloadLength]                                        = 13 Bytes
//
// * `index` < dataTotal              → Datenfragment index
// * dataTotal <= `index` < dataTotal+parityTotal → Paritaetsfragment
//                                       (index - dataTotal)
// * `payloadLength` traegt die Originallaenge, weil fuer die XOR-Paritaet
//   ALLE Fragmente gleich lang sein muessen; das letzte Datenfragment wird
//   dafuer mit Nullen aufgefuellt und beim Zusammensetzen wieder getrimmt.
//
// Warum ein eigenes Magic und nicht ein Bit im bestehenden Header: im
// CFRA-Header ist kein Bit frei (fragmentId nutzt alle 16, index und total
// je alle 8 Bits), und eine Umdeutung bestehender Bits wuerde Fragmente
// alter Sender still fehlklassifizieren — genau die stille Falschbehandlung,
// die hier vermieden werden soll. Ein unbekanntes Magic wird von alten
// Knoten stattdessen verworfen, also laut statt leise. Das ist mit der
// Entscheidung "Version 3.2.0, keine Rueckwaertskompatibilitaet" (§10.4)
// gedeckt: Video kommt heute auf vier von fuenf Plattformen ohnehin nicht an.

/// Magic bytes to identify a fragmented UDP packet: "CFRA" (Cleona Fragment)
const List<int> fragmentMagic = [0x43, 0x46, 0x52, 0x41];

/// Magic bytes for a live-media fragment: "CFRL" (Cleona Fragment Live).
///
/// §10.3.1 / I8 — carries FEC parity instead of qualifying for NACK retry.
const List<int> liveFragmentMagic = [0x43, 0x46, 0x52, 0x4C];

/// Magic bytes for fragment NACK: "CFNK" (Cleona Fragment NACK)
const List<int> fragmentNackMagic = [0x43, 0x46, 0x4E, 0x4B];

/// Maximum fragment payload size (excluding header).
/// 1200 bytes total - 4 bytes magic - 4 bytes header = 1192 bytes payload.
const int maxFragmentPayloadSize = 1192;

/// Total fragment packet size (magic + header + payload).
const int maxFragmentPacketSize = 1200;

/// Fragment header size: 4 bytes magic + 2 bytes fragmentId + 1 byte index + 1 byte total.
const int fragmentHeaderSize = 8;

/// Live-media fragment header size: 4 magic + 2 fragmentId + 1 index
/// + 1 dataTotal + 1 parityTotal + 4 payloadLength.
const int liveFragmentHeaderSize = 13;

/// Payload bytes per live-media fragment (1200 - 13).
const int maxLiveFragmentPayloadSize =
    maxFragmentPacketSize - liveFragmentHeaderSize;

class UdpFragmenter {
  /// Data fragments per XOR parity fragment for live media (§10.3.1, I8).
  ///
  /// **Provisorisch, ausdruecklich nicht gemessen.** Vier ergibt ein
  /// Paritaetsfragment je vier Datenfragmente (25 % Overhead) und garantiert
  /// bei jeder fragmentierten Rahmengroesse — die kleinste ist zwei
  /// Fragmente — mindestens ein Paritaetsfragment. Der Wert steht unter
  /// Spec §10 Gate 6 ("gemessen, nicht plausibel"): bevor die Zustellgrenze
  /// fuer Live-Media nach Erratum E4 angehoben werden darf, MUSS er aus
  /// einer Messung des ausgelieferten Pfades neu abgeleitet werden. Genau
  /// deshalb hebt Paket V1.11 die Grenze nicht an — siehe
  /// [liveMediaMaxFrameBytes].
  static const int liveFecGroupSize = 4;

  /// Hard ceiling on wire fragments per group — `index` is one byte, so
  /// data + parity must stay <= 255. Same structural limit as the 255 of
  /// the classic CFRA path, only shared with the parity fragments.
  static const int maxWireFragments = 255;

  /// Largest number of DATA fragments a live-media frame may occupy.
  ///
  /// Derived, not chosen: with `parityTotal = ceil(d / liveFecGroupSize)`
  /// the wire count is `d + ceil(d/4)`, and 204 + 51 = 255 is the largest
  /// `d` that still fits the one-byte index.
  static const int maxLiveDataFragments = 204;

  /// §10.3.1 / I9 — the plain-UDP delivery envelope for ONE live-media
  /// frame, in bytes. This is the single source of the value; nothing else
  /// in the tree may keep a second copy (V1.17 consumes it via
  /// `CleonaNode.liveMediaMaxFrameBytes`).
  ///
  /// 204 * 1187 = 242'148 B. Structural, not a taste value: it falls out of
  /// the one-byte fragment index and the 25 % parity share. It is
  /// deliberately NOT the ten-fragment TLS-escalation threshold — Erratum E4
  /// calls those ten an escalation heuristic without measurement basis and
  /// therefore not an admissible reference.
  static const int liveMediaMaxFrameBytes =
      maxLiveDataFragments * maxLiveFragmentPayloadSize;

  /// Number of XOR parity fragments generated for [dataTotal] data
  /// fragments. Interleaved: data fragment `i` belongs to parity group
  /// `i % parityTotal`, so a burst of up to `parityTotal` CONSECUTIVE lost
  /// fragments hits `parityTotal` distinct groups and is fully recoverable.
  /// Contiguous grouping would lose an entire group to the same burst.
  static int parityCountFor(int dataTotal) {
    if (dataTotal <= 0) return 0;
    return (dataTotal + liveFecGroupSize - 1) ~/ liveFecGroupSize;
  }

  /// Fragment a payload into chunks suitable for UDP.
  ///
  /// Returns a list of raw packets (each <= 1200 bytes).
  /// If the payload fits in a single packet, returns it unchanged (no fragmentation).
  ///
  /// [liveMedia] selects the CFRL framing with FEC parity instead of the
  /// CFRA framing with NACK retry (§10.3.1, I8). The caller — and only the
  /// caller — knows the message type; this function never guesses it from
  /// size or content.
  static List<Uint8List> fragment(Uint8List payload,
      {int? fragmentId, bool liveMedia = false}) {
    if (payload.length <= maxFragmentPacketSize) {
      return [payload]; // Fits in one UDP packet — no fragmentation needed
    }
    if (liveMedia) return fragmentLive(payload, fragmentId: fragmentId);

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

  /// Fragment a live-media payload into CFRL data fragments plus
  /// interleaved XOR parity fragments (§10.3.1, I8 — FEC instead of
  /// retransmit).
  ///
  /// Throws [ArgumentError] when the frame exceeds [liveMediaMaxFrameBytes].
  /// The caller must treat that as the defect it is (Erratum E1: a dropped
  /// live frame is counted and logged, never discarded silently) — see
  /// `CleonaNode.liveMediaFramesDroppedOversize`.
  static List<Uint8List> fragmentLive(Uint8List payload, {int? fragmentId}) {
    if (payload.isEmpty) return const [];
    final dataTotal = (payload.length / maxLiveFragmentPayloadSize).ceil();
    if (dataTotal > maxLiveDataFragments) {
      throw ArgumentError('Live-media frame too large: ${payload.length} B = '
          '$dataTotal data fragments (max $maxLiveDataFragments, '
          '$liveMediaMaxFrameBytes B)');
    }
    final parityTotal = parityCountFor(dataTotal);
    final fid = fragmentId ?? _nextFragmentId();

    // Zero-padded equal-length chunks — XOR parity is only defined over
    // equally sized words. The original length travels in the header so the
    // receiver can trim the padding back off.
    final chunks = List<Uint8List>.generate(dataTotal, (i) {
      final chunk = Uint8List(maxLiveFragmentPayloadSize);
      final start = i * maxLiveFragmentPayloadSize;
      final end = (start + maxLiveFragmentPayloadSize) > payload.length
          ? payload.length
          : start + maxLiveFragmentPayloadSize;
      chunk.setRange(0, end - start, payload, start);
      return chunk;
    });

    final out = <Uint8List>[];
    for (var i = 0; i < dataTotal; i++) {
      out.add(_buildLiveFragment(
          fid, i, dataTotal, parityTotal, payload.length, chunks[i]));
    }
    for (var j = 0; j < parityTotal; j++) {
      final parity = Uint8List(maxLiveFragmentPayloadSize);
      for (var i = j; i < dataTotal; i += parityTotal) {
        final src = chunks[i];
        for (var b = 0; b < maxLiveFragmentPayloadSize; b++) {
          parity[b] ^= src[b];
        }
      }
      out.add(_buildLiveFragment(fid, dataTotal + j, dataTotal, parityTotal,
          payload.length, parity));
    }
    return out;
  }

  static Uint8List _buildLiveFragment(int fid, int index, int dataTotal,
      int parityTotal, int payloadLength, Uint8List chunk) {
    final packet = Uint8List(liveFragmentHeaderSize + chunk.length);
    packet[0] = liveFragmentMagic[0];
    packet[1] = liveFragmentMagic[1];
    packet[2] = liveFragmentMagic[2];
    packet[3] = liveFragmentMagic[3];
    packet[4] = (fid >> 8) & 0xFF;
    packet[5] = fid & 0xFF;
    packet[6] = index;
    packet[7] = dataTotal;
    packet[8] = parityTotal;
    packet[9] = (payloadLength >> 24) & 0xFF;
    packet[10] = (payloadLength >> 16) & 0xFF;
    packet[11] = (payloadLength >> 8) & 0xFF;
    packet[12] = payloadLength & 0xFF;
    packet.setRange(liveFragmentHeaderSize, packet.length, chunk);
    return packet;
  }

  /// Check if a raw UDP packet is a fragment (classic CFRA or live CFRL).
  static bool isFragment(Uint8List data) => isBulkFragment(data) || isLiveFragment(data);

  /// Classic, NACK-eligible fragment ("CFRA").
  static bool isBulkFragment(Uint8List data) {
    return data.length >= fragmentHeaderSize &&
        data[0] == fragmentMagic[0] &&
        data[1] == fragmentMagic[1] &&
        data[2] == fragmentMagic[2] &&
        data[3] == fragmentMagic[3];
  }

  /// Live-media fragment ("CFRL") — FEC-protected, never NACK'd (I8).
  static bool isLiveFragment(Uint8List data) {
    return data.length >= liveFragmentHeaderSize &&
        data[0] == liveFragmentMagic[0] &&
        data[1] == liveFragmentMagic[1] &&
        data[2] == liveFragmentMagic[2] &&
        data[3] == liveFragmentMagic[3];
  }

  /// True iff bytes 1..3 of a 4-byte magic belong to one of the fragment
  /// magics this module owns. The transport's wire-layer discriminator
  /// (`_processUdpDatagram`) uses it so a new fragment magic never has to be
  /// re-typed there — the list has exactly one home.
  static bool matchesFragmentMagicTail(int m1, int m2, int m3) =>
      (m1 == fragmentMagic[1] &&
          m2 == fragmentMagic[2] &&
          m3 == fragmentMagic[3]) ||
      (m1 == liveFragmentMagic[1] &&
          m2 == liveFragmentMagic[2] &&
          m3 == liveFragmentMagic[3]) ||
      (m1 == fragmentNackMagic[1] &&
          m2 == fragmentNackMagic[2] &&
          m3 == fragmentNackMagic[3]);

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

  /// Parse fragment header from a raw packet (CFRA or CFRL).
  static FragmentHeader? parseHeader(Uint8List data) {
    if (isLiveFragment(data)) {
      final index = data[6];
      final dataTotal = data[7];
      final parityTotal = data[8];
      if (dataTotal < 1) return null;
      if (dataTotal + parityTotal > maxWireFragments) return null;
      if (index >= dataTotal + parityTotal) return null;
      final payloadLength =
          (data[9] << 24) | (data[10] << 16) | (data[11] << 8) | data[12];
      // A frame claiming more bytes than its data fragments can hold is
      // malformed — reject rather than trim to a wrong length later.
      if (payloadLength < 1 ||
          payloadLength > dataTotal * maxLiveFragmentPayloadSize) {
        return null;
      }
      return FragmentHeader(
        fragmentId: (data[4] << 8) | data[5],
        index: index,
        total: dataTotal + parityTotal,
        liveMedia: true,
        dataTotal: dataTotal,
        parityTotal: parityTotal,
        payloadLength: payloadLength,
      );
    }
    if (!isBulkFragment(data)) return null;

    final index = data[6];
    final total = data[7];
    if (total < 1 || index >= total) return null;

    return FragmentHeader(
      fragmentId: (data[4] << 8) | data[5],
      index: index,
      total: total,
      dataTotal: total,
    );
  }

  /// Extract payload from a fragment packet (strip magic + header).
  static Uint8List extractPayload(Uint8List data) {
    final headerSize =
        isLiveFragment(data) ? liveFragmentHeaderSize : fragmentHeaderSize;
    if (data.length <= headerSize) return Uint8List(0);
    return Uint8List.fromList(data.sublist(headerSize));
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
  final int total;      // 1-255 — wire fragments in this group (data + parity)

  /// True for CFRL fragments: FEC-protected live media, exempt from NACK
  /// retry (§10.3.1, I8).
  final bool liveMedia;

  /// Data fragments in this group. Equals [total] for classic fragments.
  final int dataTotal;

  /// XOR parity fragments in this group. Always 0 for classic fragments.
  final int parityTotal;

  /// Original payload length in bytes — live media only (the last data
  /// fragment is zero-padded so parity is defined). 0 for classic
  /// fragments, whose length falls out of the assembled chunks.
  final int payloadLength;

  FragmentHeader({
    required this.fragmentId,
    required this.index,
    required this.total,
    this.liveMedia = false,
    int? dataTotal,
    this.parityTotal = 0,
    this.payloadLength = 0,
  }) : dataTotal = dataTotal ?? total;

  /// True iff this fragment carries XOR parity rather than payload bytes.
  bool get isParity => liveMedia && index >= dataTotal;

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

  /// Hard limit for an incomplete LIVE-media group (§10.3.1).
  ///
  /// Abgeleitet aus der Frame-Deadline, nicht gewaehlt: §10.3.1 nennt
  /// 20-33 ms pro Frame und begruendet damit, warum ein Retry nach 500 ms
  /// zu spaet ist. 200 ms sind sechs bis zehn Sendeintervalle — was bis
  /// dahin nicht vollstaendig ist, kommt nicht mehr rechtzeitig, und ein
  /// laengeres Fenster kostet bei 50 Frames/s nur Speicher.
  static const Duration liveReassemblyTimeout = Duration(milliseconds: 200);

  /// Live-media groups that even FEC could not reconstruct (diagnostic).
  /// Non-zero is expected under loss — this is NOT a defect counter, unlike
  /// `CleonaNode.liveMediaFramesDroppedOversize` (Erratum E1).
  int liveMediaFramesUnrecovered = 0;

  /// Live-media groups reconstructed from XOR parity — i.e. frames that
  /// would have been lost (or NACK-retried far too late) before V1.11.
  int liveMediaFramesRecoveredByFec = 0;

  /// How often a NACK retry timer was armed, over all buffers.
  ///
  /// Exists to make I8's NACK half observable at its enforcement point
  /// rather than at a downstream symptom. Counting delivered NACKs instead
  /// would be a gate that only looks like one: a live buffer expires after
  /// [liveReassemblyTimeout] (200 ms) while the first NACK is due at
  /// [nackDelayInitial] (500 ms), so no NACK reaches the wire even when the
  /// exemption is removed — the timer is simply armed against a buffer that
  /// is gone. This counter sees the arming itself and therefore fails when
  /// the exemption is taken away.
  int nackTimersArmed = 0;

  /// Hard cap on concurrent reassembly buffers to prevent memory exhaustion.
  /// 255 fragments × 1200B = ~300KB per buffer; 256 buffers ≈ 75MB worst case.
  static const int maxBuffers = 256;

  /// Initial delay before sending first NACK after last fragment received.
  static const Duration nackDelayInitial = Duration(milliseconds: 500);

  /// Maximum NACK delay (backoff cap).
  static const Duration nackDelayCap = Duration(milliseconds: 2000);

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
    if (buffer != null &&
        (buffer.total != header.total ||
            buffer.liveMedia != header.liveMedia)) {
      // Different total (or a live group landing on a bulk key) = different
      // message on the same key (NAT collision).
      buffer.nackTimer?.cancel();
      _buffers.remove(key);
      onLog?.call('Fragment collision (total ${buffer.total}→${header.total}, '
          'live ${buffer.liveMedia}→${header.liveMedia}): '
          'key=$key — reset buffer');
      buffer = null;
    }
    if (buffer == null) {
      if (_buffers.length >= maxBuffers) {
        // Evict oldest buffer to stay within memory budget.
        String? oldestKey;
        DateTime? oldestTime;
        for (final e in _buffers.entries) {
          if (oldestTime == null || e.value.createdAt.isBefore(oldestTime)) {
            oldestKey = e.key;
            oldestTime = e.value.createdAt;
          }
        }
        if (oldestKey != null) {
          _buffers.remove(oldestKey)!.nackTimer?.cancel();
          onLog?.call('Fragment buffer evicted (cap=$maxBuffers): key=$oldestKey');
        }
      }
      buffer = _ReassemblyBuffer(
        fragmentId: header.fragmentId,
        total: header.total,
        sourceIp: sourceIp,
        sourcePort: sourcePort,
        createdAt: DateTime.now(),
        liveMedia: header.liveMedia,
        dataTotal: header.dataTotal,
        parityTotal: header.parityTotal,
        payloadLength: header.payloadLength,
      );
      _buffers[key] = buffer;
      onLog?.call('Fragment buffer created: key=$key total=${header.total} '
          '${header.liveMedia ? "live(d=${header.dataTotal},p=${header.parityTotal}) " : ""}'
          'from $sourceIp:$sourcePort');

      // Hard timeout — cleanup even if NACKs are pending.
      // Live media uses [liveReassemblyTimeout]: at call framerate a 10 s
      // buffer lifetime would keep hundreds of dead groups alive, and a
      // frame that is still incomplete after several send intervals is
      // stale by construction (§10.3.1: 20-33 ms deadline).
      final bufferRef = buffer;
      Timer(header.liveMedia ? liveReassemblyTimeout : reassemblyTimeout, () {
        if (_buffers[key] != bufferRef) return;
        final expired = _buffers.remove(key);
        if (expired != null) {
          expired.nackTimer?.cancel();
          if (expired.fragments.length < expired.total) {
            if (expired.liveMedia) {
              liveMediaFramesUnrecovered++;
            }
            onLog?.call('Fragment buffer EXPIRED: key=$key '
                'got=${expired.fragments.length}/${expired.total} '
                '${expired.liveMedia ? "live (FEC insufficient) " : ""}'
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

    // ── Live media (§10.3.1, I8): FEC instead of retransmit ──────────
    //
    // Two things differ from the classic path, and both are the point of
    // this package:
    //  1. completeness means "all DATA fragments present or reconstructible
    //     from parity", not "all wire fragments arrived";
    //  2. no NACK timer is ever armed — not on this branch, not below.
    if (buffer.liveMedia) {
      final assembled = _assembleLive(buffer);
      if (assembled != null) {
        _buffers.remove(key);
        onLog?.call('Live fragment group complete: key=$key '
            '${buffer.fragments.length}/${buffer.total} '
            '(d=${buffer.dataTotal}, p=${buffer.parityTotal})');
        return assembled;
      }
      return null;
    }

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

  /// Compute NACK delay with exponential backoff: 500ms, 750ms, 1000ms,
  /// 1500ms, 2000ms, 2000ms, ... (cap at [nackDelayCap]).
  Duration _nackDelayForRound(int nackCount) {
    final ms = nackDelayInitial.inMilliseconds *
        (1 << (nackCount < 3 ? nackCount : 2));
    return Duration(milliseconds: ms.clamp(0, nackDelayCap.inMilliseconds));
  }

  /// Arm the NACK retry timer for a classic (CFRA) reassembly.
  ///
  /// Live-media buffers never reach this: [addFragment] returns from its
  /// `buffer.liveMedia` branch before the call site below. That single early
  /// return is the whole enforcement of I8's NACK half — deliberately one
  /// place, so it can be removed in a negative control and actually fail.
  void _scheduleNack(String key, _ReassemblyBuffer buffer) {
    nackTimersArmed++;
    buffer.nackTimer?.cancel();
    final delay = _nackDelayForRound(buffer.nackCount);
    // Guard: cumulative NACK time must stay within the hard reassembly
    // timeout. If the next NACK would fire after the buffer expires, stop.
    final elapsed = DateTime.now().difference(buffer.createdAt);
    if (elapsed + delay >= reassemblyTimeout) return;
    buffer.nackTimer = Timer(delay, () {
      final current = _buffers[key];
      if (current == null) return;
      if (current.fragments.length == current.total) return;

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

  /// Assemble a live-media group, repairing single-loss parity groups from
  /// XOR parity (§10.3.1, I8 — FEC instead of retransmit).
  ///
  /// Returns null while the group is still unrecoverable; the caller keeps
  /// the buffer until [liveReassemblyTimeout] expires it.
  Uint8List? _assembleLive(_ReassemblyBuffer buffer) {
    final d = buffer.dataTotal;
    final p = buffer.parityTotal;

    // Fast path: every data fragment arrived, parity is irrelevant.
    var missingData = 0;
    for (var i = 0; i < d; i++) {
      if (!buffer.fragments.containsKey(i)) missingData++;
    }
    if (missingData == 0) return _trimLive(buffer);
    if (p == 0) return null;

    // A parity group can repair at most one missing member, so bail out as
    // soon as any group is short by two. Interleaved membership
    // (i % p == j) means a burst of consecutive losses spreads across
    // groups instead of destroying one.
    final repaired = <int, Uint8List>{};
    for (var j = 0; j < p; j++) {
      final missing = <int>[];
      for (var i = j; i < d; i += p) {
        if (!buffer.fragments.containsKey(i)) missing.add(i);
      }
      if (missing.isEmpty) continue;
      if (missing.length > 1) return null; // unrecoverable, wait or expire
      final parity = buffer.fragments[d + j];
      if (parity == null) return null; // parity itself lost — nothing to do
      final recovered = Uint8List.fromList(parity);
      for (var i = j; i < d; i += p) {
        if (i == missing.first) continue;
        final src = buffer.fragments[i]!;
        final n = recovered.length < src.length ? recovered.length : src.length;
        for (var b = 0; b < n; b++) {
          recovered[b] ^= src[b];
        }
      }
      repaired[missing.first] = recovered;
    }
    if (repaired.isEmpty) return null;
    buffer.fragments.addAll(repaired);
    liveMediaFramesRecoveredByFec++;
    onLog?.call('Live FEC repair: fragmentId=${buffer.fragmentId} '
        'recovered=${repaired.length}/$d data fragments from parity');
    return _trimLive(buffer);
  }

  /// Concatenate the data fragments of a live group and cut the zero
  /// padding of the last one back off.
  Uint8List? _trimLive(_ReassemblyBuffer buffer) {
    final result = Uint8List(buffer.payloadLength);
    var offset = 0;
    for (var i = 0; i < buffer.dataTotal; i++) {
      final frag = buffer.fragments[i];
      if (frag == null) return null;
      final remaining = buffer.payloadLength - offset;
      if (remaining <= 0) break;
      final take = frag.length < remaining ? frag.length : remaining;
      result.setRange(offset, offset + take, frag);
      offset += take;
    }
    if (offset != buffer.payloadLength) return null;
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

  /// CFRL group (§10.3.1, I8) — FEC-protected, never NACK'd.
  final bool liveMedia;
  final int dataTotal;
  final int parityTotal;
  final int payloadLength;

  _ReassemblyBuffer({
    required this.fragmentId,
    required this.total,
    required this.sourceIp,
    required this.sourcePort,
    required this.createdAt,
    this.liveMedia = false,
    int? dataTotal,
    this.parityTotal = 0,
    this.payloadLength = 0,
  }) : dataTotal = dataTotal ?? total;
}
