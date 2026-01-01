import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/crypto/hd_wallet.dart';
import 'package:cleona/core/crypto/network_secret.dart';
import 'package:cleona/core/network/compression.dart';
import 'package:cleona/core/network/peer_info.dart' show hexToBytes, bytesToHex;
import 'package:cleona/core/service/service_types.dart' show PeerSummary;

/// ContactSeed: encodes node identity + reachability into a URI for QR codes.
///
/// Two format generations (§8.1.1):
///
/// **URI format (clipboard/share)** — includes Device-KEM-PK for offline first-CR:
/// `cleona://<userIdHex>?n=<name>&c=<b|l>&did=<deviceIdHex>&ep=<…>&dxk=<…>&dmk=<…>&a=<addrs>&s=<seedPeers>`
///
/// **QR binary format** — compact v2 (ep only, ~350 chars, QR Version 8-10).
///
/// - nodeIdHex: 64-char hex of the user's 32-byte UserID (§8.1.1).
/// - n: display name (URL-encoded)
/// - c: network channel ('b' = beta, 'l' = live)
/// - did: deviceId (64-char hex)
/// - ep: userEd25519Pk, 32 bytes, base64url — trust-anchor for Deferred
///   Key Exchange and DHT record verification. Integrity: SHA-256(networkSecret + ep) == nodeIdHex.
/// - dxk/dmk: Device-KEM keys (X25519 32B + ML-KEM-768 1184B, standard base64).
///   Enables offline first-CR on CGNAT without synchronous DEVICE_KEM_REQUEST.
/// - a: own addresses (multi-address, + encoded as %2B)
/// - s: seed peers (up to 5, each: nodeIdHex@ip:port+ip:port)
class ContactSeed {
  /// Length of the X25519 public key in bytes.
  static const int deviceX25519PkLength = 32;

  /// Length of the ML-KEM-768 public key in bytes.
  static const int deviceMlKemPkLength = 1184;

  final String nodeIdHex;
  final String displayName;
  final List<String> ownAddresses; // ip:port pairs
  final List<SeedPeer> seedPeers;
  final String? channelTag; // 'b' or 'l' (null = legacy QR without channel)
  final String? deviceIdHex; // 64-char hex (null = legacy QR without device_id)

  /// User-Ed25519 public key (v2 rev3). 32 bytes, base64url in URI.
  /// Trust-anchor for Deferred Key Exchange: verifies DHT DeviceKemRecords
  /// and DEVICE_KEM_OFFER signatures (§8.1.1).
  final Uint8List? userEd25519Pk;

  /// Device-X25519 public key. 32 bytes. Included in URI format to enable
  /// offline first-CR (FIRST_CR_STORE) without Deferred Key Exchange.
  final Uint8List? deviceX25519Pk;

  /// Device-ML-KEM-768 public key. 1184 bytes.
  final Uint8List? deviceMlKemPk;

  /// ContactSeed creation time (ms since epoch, §8.1.1 rev3 — URI `t`,
  /// QR format 0x07/0x08). null = legacy seed without a timestamp (age
  /// unknown). Lets the scanner distinguish a stale seed ("request a fresh
  /// code") from an offline target. Outside the integrity-check input.
  final int? createdAtMs;

  /// SR-2 (§8.1.1 / §3.1 stable anchor): founding User-Ed25519 pubkey —
  /// the key whose hash IS the userId. Only emitted when the identity has
  /// soft-re-keyed (`fp != ep`); the integrity check then anchors on `fp`
  /// instead of `ep`. The binding founding→current `ep` is proven by the
  /// rotation chain in the D1-verified Auth-Manifest at first resolution
  /// (§4.3 path 2). URI param `fp`, QR formats 0x09/0x0A.
  final Uint8List? foundingEd25519Pk;

  ContactSeed({
    required this.nodeIdHex,
    required this.displayName,
    this.ownAddresses = const [],
    this.seedPeers = const [],
    this.channelTag,
    this.deviceIdHex,
    this.userEd25519Pk,
    this.deviceX25519Pk,
    this.deviceMlKemPk,
    this.createdAtMs,
    this.foundingEd25519Pk,
  });

  /// §8.1.1 integrity check (SR-2): `SHA-256(networkSecret + fp) == userId`
  /// for rotated identities (fp present), else against `ep`. Returns null
  /// when the seed carries no anchor at all (v1 legacy without ep — not
  /// checkable, callers treat as pass for backward compat).
  bool? verifyIntegrity() {
    final anchor = foundingEd25519Pk ?? userEd25519Pk;
    if (anchor == null || anchor.length != 32) return null;
    final derived =
        HdWallet.computeUserId(anchor, NetworkSecret.secret);
    return bytesToHex(derived) == nodeIdHex.toLowerCase();
  }

  /// Age of this seed if it carries a creation timestamp, else null.
  Duration? ageFrom(DateTime now) =>
      createdAtMs == null ? null : now.difference(DateTime.fromMillisecondsSinceEpoch(createdAtMs!));

  /// Build the URI string for clipboard / share (includes Device-KEM-PK
  /// when available so CGNAT-to-CGNAT first-CR works without synchronous
  /// DEVICE_KEM_REQUEST round-trip). QR uses [toQrBytes] (compact v2).
  String toUri() {
    final sb = StringBuffer('cleona://$nodeIdHex');
    sb.write('?n=${Uri.encodeComponent(displayName)}');

    // Channel tag: 1 char ('b' = beta, 'l' = live)
    if (channelTag != null) {
      sb.write('&c=$channelTag');
    }

    // Device ID: 64-char hex (V3.0 2-Layer-Frames). Optional for backward compat.
    if (deviceIdHex != null && deviceIdHex!.isNotEmpty) {
      sb.write('&did=$deviceIdHex');
    }

    // v2 (rev3): userEd25519Pk as trust-anchor, base64url (RFC 4648 §5).
    final ep = userEd25519Pk;
    if (ep != null && ep.length == 32) {
      sb.write('&ep=${base64Url.encode(ep).replaceAll('=', '')}');
    }

    // Device-KEM-PK: enables offline first-CR (FIRST_CR_STORE on seed
    // peers) without Deferred Key Exchange. Critical for CGNAT-to-CGNAT
    // clipboard exchange where both phones may not be online simultaneously.
    final dxk = deviceX25519Pk;
    final dmk = deviceMlKemPk;
    if (dxk != null && dxk.length == deviceX25519PkLength &&
        dmk != null && dmk.length == deviceMlKemPkLength) {
      sb.write('&dxk=${base64.encode(dxk)}');
      sb.write('&dmk=${base64.encode(dmk)}');
    }

    // Creation timestamp (rev3): lets the scanner judge seed freshness.
    if (createdAtMs != null) {
      sb.write('&t=$createdAtMs');
    }

    // SR-2: founding pubkey — only for rotated identities (fp != ep).
    final fp = foundingEd25519Pk;
    if (fp != null && fp.length == 32 && !_sameBytes(fp, ep)) {
      sb.write('&fp=${base64Url.encode(fp).replaceAll('=', '')}');
    }

    if (ownAddresses.isNotEmpty) {
      // Join with + but encode as %2B in URI
      final joined = ownAddresses.join('+');
      sb.write('&a=${joined.replaceAll('+', '%2B')}');
    }

    if (seedPeers.isNotEmpty) {
      final peers = seedPeers.take(5).map((p) {
        final addrs = p.addresses.take(2).join('+');
        return '${p.nodeIdHex}@${addrs.replaceAll('+', '%2B')}';
      }).join(',');
      sb.write('&s=$peers');
    }

    return sb.toString();
  }

  /// Parse a ContactSeed URI.
  /// Returns null if the URI is malformed.
  static ContactSeed? fromUri(String uri) {
    try {
      if (!uri.startsWith('cleona://')) return null;

      final withoutScheme = uri.substring('cleona://'.length);
      final qIdx = withoutScheme.indexOf('?');
      if (qIdx < 0) return null;

      final nodeIdHex = withoutScheme.substring(0, qIdx);
      if (nodeIdHex.length != 64) return null;

      final queryString = withoutScheme.substring(qIdx + 1);
      final params = _parseQuery(queryString);

      final name = params['n'] ?? '';

      // Parse own addresses
      final ownAddrs = <String>[];
      final aParam = params['a'];
      if (aParam != null && aParam.isNotEmpty) {
        ownAddrs.addAll(aParam.split('+').where((a) => a.isNotEmpty));
      }

      // Parse seed peers
      final seedPeers = <SeedPeer>[];
      final sParam = params['s'];
      if (sParam != null && sParam.isNotEmpty) {
        for (final peerStr in sParam.split(',')) {
          final atIdx = peerStr.indexOf('@');
          if (atIdx < 0) continue;
          final peerNodeId = peerStr.substring(0, atIdx);
          final addrs = peerStr.substring(atIdx + 1).split('+').where((a) => a.isNotEmpty).toList();
          seedPeers.add(SeedPeer(nodeIdHex: peerNodeId, addresses: addrs));
        }
      }

      // Parse device_id (V3.0). Validate 64-char hex; treat malformed as absent
      // to preserve backward compatibility (legacy QRs without `did` parse fine).
      String? deviceIdHex;
      final didParam = params['did'];
      if (didParam != null && didParam.length == 64 &&
          RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(didParam)) {
        deviceIdHex = didParam.toLowerCase();
      }

      // v2 (rev3): userEd25519Pk as trust-anchor (base64url, no padding).
      Uint8List? ep;
      final epParam = params['ep'];
      if (epParam != null && epParam.isNotEmpty) {
        try {
          final decoded = base64Url.decode(base64Url.normalize(epParam));
          if (decoded.length == 32) {
            ep = Uint8List.fromList(decoded);
          }
        } catch (_) {}
      }

      // Device-KEM pubkeys (standard base64). URIs with dxk+dmk skip the
      // Deferred Key Exchange — enables offline first-CR on CGNAT.
      Uint8List? dxk;
      Uint8List? dmk;
      final dxkParam = params['dxk'];
      if (dxkParam != null && dxkParam.isNotEmpty) {
        try {
          final decoded = base64.decode(dxkParam);
          if (decoded.length == deviceX25519PkLength) {
            dxk = Uint8List.fromList(decoded);
          }
        } catch (_) {}
      }
      final dmkParam = params['dmk'];
      if (dmkParam != null && dmkParam.isNotEmpty) {
        try {
          final decoded = base64.decode(dmkParam);
          if (decoded.length == deviceMlKemPkLength) {
            dmk = Uint8List.fromList(decoded);
          }
        } catch (_) {}
      }

      // Creation timestamp (rev3, optional). Legacy URIs without `t` → null.
      int? createdAt;
      final tParam = params['t'];
      if (tParam != null && tParam.isNotEmpty) {
        createdAt = int.tryParse(tParam);
      }

      // SR-2: founding pubkey (rotated identities only).
      Uint8List? fp;
      final fpParam = params['fp'];
      if (fpParam != null && fpParam.isNotEmpty) {
        try {
          final decoded = base64Url.decode(base64Url.normalize(fpParam));
          if (decoded.length == 32) {
            fp = Uint8List.fromList(decoded);
          }
        } catch (_) {}
      }

      return ContactSeed(
        nodeIdHex: nodeIdHex,
        displayName: name,
        ownAddresses: ownAddrs,
        seedPeers: seedPeers,
        channelTag: params['c'],
        deviceIdHex: deviceIdHex,
        userEd25519Pk: ep,
        deviceX25519Pk: dxk,
        deviceMlKemPk: dmk,
        createdAtMs: createdAt,
        foundingEd25519Pk: fp,
      );
    } catch (_) {
      return null;
    }
  }

  /// Manual query string parser that handles %2B → + correctly.
  static Map<String, String> _parseQuery(String query) {
    final params = <String, String>{};
    for (final part in query.split('&')) {
      final eqIdx = part.indexOf('=');
      if (eqIdx < 0) continue;
      final key = part.substring(0, eqIdx);
      var value = part.substring(eqIdx + 1);
      // Decode %2B back to + BEFORE URI decoding
      value = value.replaceAll('%2B', '+');
      try {
        value = Uri.decodeComponent(value);
      } catch (_) {
        // Keep raw value if decode fails (e.g., malformed percent-encoding)
      }
      params[key] = value;
    }
    return params;
  }

  /// Check if this seed's channel matches the local channel.
  /// Returns true if compatible (same channel or legacy QR without tag).
  bool isChannelCompatible(String localChannelTag) {
    if (channelTag == null || channelTag!.isEmpty) return true; // legacy
    return channelTag == localChannelTag;
  }

  /// Human-readable channel name for error messages.
  String get channelDisplayName {
    if (channelTag == 'b') return 'Beta';
    if (channelTag == 'l') return 'Live';
    return '?';
  }

  // --- Compact binary QR format ---
  //
  // v2 (rev3, format 0x03/0x04): 32B ep instead of 1216B dxk+dmk → QR Version 8-10.
  // v1 (legacy, format 0x01/0x02): 32B dxk + 1184B dmk → QR Version 26-28.
  //
  // Wire: [1B format] [payload]
  //   format 0x03 = zstd-compressed v2
  //   format 0x04 = uncompressed v2
  //   format 0x01 = zstd-compressed v1 (legacy)
  //   format 0x02 = uncompressed v1 (legacy)
  //
  // v2 binary payload (format 0x03/0x04 legacy; 0x07/0x08 add [8B createdAtMs]):
  //   [32B userId] [32B deviceId] [32B userEd25519Pk]
  //   [8B createdAtMs]        ← only in format 0x07 (zstd) / 0x08 (uncompressed)
  //   [1B channel] [1B nameLen] [nameUTF8]
  //   [1B addrCount] [{1B len, addrUTF8}...]
  //   [1B peerCount] [{32B nodeId, 1B addrCount, {1B len, addrUTF8}...}...]

  Uint8List toQrBytes() {
    final bb = BytesBuilder(copy: false);

    bb.add(hexToBytes(nodeIdHex));

    if (deviceIdHex != null && deviceIdHex!.length == 64) {
      bb.add(hexToBytes(deviceIdHex!));
    } else {
      bb.add(Uint8List(32));
    }

    bb.add(userEd25519Pk ?? Uint8List(32));

    // SR-2: founding pubkey present and distinct from ep → format 0x09/0x0A
    // (= 0x07/0x08 layout + 32B fp after the timestamp). The timestamp slot
    // is then always written (0 when unset) so the layout stays fixed.
    final hasFp = foundingEd25519Pk != null &&
        foundingEd25519Pk!.length == 32 &&
        !_sameBytes(foundingEd25519Pk!, userEd25519Pk);

    // rev3: 8-byte big-endian creation timestamp — only emitted in the new
    // format bytes 0x07/0x08 (and always in 0x09/0x0A). Legacy 0x03/0x04
    // omit it (age then unknown).
    final hasTs = createdAtMs != null || hasFp;
    if (hasTs) {
      final tsBytes = Uint8List(8);
      ByteData.view(tsBytes.buffer).setUint64(0, createdAtMs ?? 0, Endian.big);
      bb.add(tsBytes);
    }
    if (hasFp) {
      bb.add(foundingEd25519Pk!);
    }

    bb.addByte(channelTag == 'b' ? 0x62 : channelTag == 'l' ? 0x6C : 0x00);

    final nameBytes = utf8.encode(displayName);
    final nameLen = nameBytes.length.clamp(0, 255);
    bb.addByte(nameLen);
    bb.add(nameBytes.sublist(0, nameLen));

    final addrs = ownAddresses.take(15).toList();
    bb.addByte(addrs.length);
    for (final a in addrs) {
      final ab = utf8.encode(a);
      final al = ab.length.clamp(0, 255);
      bb.addByte(al);
      bb.add(ab.sublist(0, al));
    }

    final peers = seedPeers.take(5).toList();
    bb.addByte(peers.length);
    for (final sp in peers) {
      bb.add(hexToBytes(sp.nodeIdHex));
      final pa = sp.addresses.take(3).toList();
      bb.addByte(pa.length);
      for (final a in pa) {
        final ab = utf8.encode(a);
        final al = ab.length.clamp(0, 255);
        bb.addByte(al);
        bb.add(ab.sublist(0, al));
      }
    }

    final raw = bb.toBytes();
    // rev3 format bytes carry the timestamp; legacy bytes do not. SR-2
    // format bytes additionally carry the founding pubkey.
    final fmtCompressed = hasFp ? 0x09 : (hasTs ? 0x07 : 0x03);
    final fmtUncompressed = hasFp ? 0x0A : (hasTs ? 0x08 : 0x04);
    try {
      final compressed = ZstdCompression.instance.compress(
          Uint8List.fromList(raw), level: 3);
      if (compressed.length < raw.length) {
        final out = BytesBuilder(copy: false);
        out.addByte(fmtCompressed);
        out.add(compressed);
        return out.toBytes();
      }
    } catch (_) {}
    final out = BytesBuilder(copy: false);
    out.addByte(fmtUncompressed);
    out.add(raw);
    return out.toBytes();
  }

  static ContactSeed? fromQrBytes(Uint8List data) {
    if (data.length < 2) return null;
    final format = data[0];
    Uint8List payload;
    // Compressed: 0x01 (v1), 0x03 (v2), 0x07 (v2+timestamp), 0x09 (SR-2 +fp).
    final isCompressed =
        format == 0x01 || format == 0x03 || format == 0x07 || format == 0x09;
    // Uncompressed: 0x02 (v1), 0x04 (v2), 0x08 (v2+timestamp), 0x0A (SR-2 +fp).
    final isUncompressed =
        format == 0x02 || format == 0x04 || format == 0x08 || format == 0x0A;
    if (isCompressed) {
      try {
        payload = ZstdCompression.instance.decompress(
            Uint8List.sublistView(data, 1));
      } catch (_) { return null; }
    } else if (isUncompressed) {
      payload = Uint8List.sublistView(data, 1);
    } else {
      return null;
    }
    final isV1 = format == 0x01 || format == 0x02;
    final hasTs = format == 0x07 || format == 0x08 || format == 0x09 || format == 0x0A;
    final hasFp = format == 0x09 || format == 0x0A;
    return isV1
        ? _parseBinaryPayload(payload)
        : _parseBinaryPayloadV2(payload, hasTs, hasFp);
  }

  static ContactSeed? _parseBinaryPayloadV2(Uint8List p,
      [bool hasTs = false, bool hasFp = false]) {
    // v2: 32+32+32+1+1+1+1 = 100 bytes minimum (+8 timestamp, +32 fp)
    if (p.length < (100 + (hasTs ? 8 : 0) + (hasFp ? 32 : 0))) return null;
    try {
      var off = 0;

      final userId = bytesToHex(Uint8List.sublistView(p, off, off + 32));
      off += 32;

      final deviceId = bytesToHex(Uint8List.sublistView(p, off, off + 32));
      off += 32;
      final hasDeviceId = deviceId != '0' * 64;

      final ep = Uint8List.fromList(p.sublist(off, off + 32));
      off += 32;
      final allZeroEp = ep.every((b) => b == 0);

      // rev3: 8-byte big-endian creation timestamp (format 0x07+ only).
      int? createdAt;
      if (hasTs) {
        createdAt = ByteData.view(p.buffer, p.offsetInBytes + off, 8)
            .getUint64(0, Endian.big);
        off += 8;
        if (createdAt == 0) createdAt = null; // fp-only seed without ts
      }

      // SR-2: 32B founding pubkey (format 0x09/0x0A only).
      Uint8List? fp;
      if (hasFp) {
        fp = Uint8List.fromList(p.sublist(off, off + 32));
        off += 32;
      }

      final chByte = p[off++];
      final channelTag = chByte == 0x62 ? 'b' : chByte == 0x6C ? 'l' : null;

      final nameLen = p[off++];
      if (off + nameLen > p.length) return null;
      final name = utf8.decode(p.sublist(off, off + nameLen), allowMalformed: true);
      off += nameLen;

      if (off >= p.length) return null;
      final addrCount = p[off++];
      final addrs = <String>[];
      for (var i = 0; i < addrCount; i++) {
        if (off >= p.length) return null;
        final al = p[off++];
        if (off + al > p.length) return null;
        addrs.add(utf8.decode(p.sublist(off, off + al), allowMalformed: true));
        off += al;
      }

      if (off >= p.length) return null;
      final peerCount = p[off++];
      final peers = <SeedPeer>[];
      for (var i = 0; i < peerCount; i++) {
        if (off + 32 > p.length) return null;
        final pId = bytesToHex(Uint8List.sublistView(p, off, off + 32));
        off += 32;
        if (off >= p.length) return null;
        final paCount = p[off++];
        final pa = <String>[];
        for (var j = 0; j < paCount; j++) {
          if (off >= p.length) return null;
          final al = p[off++];
          if (off + al > p.length) return null;
          pa.add(utf8.decode(p.sublist(off, off + al), allowMalformed: true));
          off += al;
        }
        peers.add(SeedPeer(nodeIdHex: pId, addresses: pa));
      }

      return ContactSeed(
        nodeIdHex: userId,
        displayName: name,
        ownAddresses: addrs,
        seedPeers: peers,
        channelTag: channelTag,
        deviceIdHex: hasDeviceId ? deviceId : null,
        userEd25519Pk: allZeroEp ? null : ep,
        createdAtMs: createdAt,
        foundingEd25519Pk: fp,
      );
    } catch (_) {
      return null;
    }
  }

  static bool _sameBytes(Uint8List a, Uint8List? b) {
    if (b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static ContactSeed? _parseBinaryPayload(Uint8List p) {
    // v1 legacy: 32+32+32+1184+1+1+1+1 = 1284 bytes minimum
    if (p.length < 1284) return null;
    try {
      var off = 0;

      final userId = bytesToHex(Uint8List.sublistView(p, off, off + 32));
      off += 32;

      final deviceId = bytesToHex(Uint8List.sublistView(p, off, off + 32));
      off += 32;
      final hasDeviceId = deviceId != '0' * 64;

      final dxk = Uint8List.fromList(p.sublist(off, off + deviceX25519PkLength));
      off += deviceX25519PkLength;
      final dmk = Uint8List.fromList(p.sublist(off, off + deviceMlKemPkLength));
      off += deviceMlKemPkLength;

      final allZeroDxk = dxk.every((b) => b == 0);
      final allZeroDmk = dmk.every((b) => b == 0);

      final chByte = p[off++];
      final channelTag = chByte == 0x62 ? 'b' : chByte == 0x6C ? 'l' : null;

      final nameLen = p[off++];
      if (off + nameLen > p.length) return null;
      final name = utf8.decode(p.sublist(off, off + nameLen), allowMalformed: true);
      off += nameLen;

      if (off >= p.length) return null;
      final addrCount = p[off++];
      final addrs = <String>[];
      for (var i = 0; i < addrCount; i++) {
        if (off >= p.length) return null;
        final al = p[off++];
        if (off + al > p.length) return null;
        addrs.add(utf8.decode(p.sublist(off, off + al), allowMalformed: true));
        off += al;
      }

      if (off >= p.length) return null;
      final peerCount = p[off++];
      final peers = <SeedPeer>[];
      for (var i = 0; i < peerCount; i++) {
        if (off + 32 > p.length) return null;
        final pId = bytesToHex(Uint8List.sublistView(p, off, off + 32));
        off += 32;
        if (off >= p.length) return null;
        final paCount = p[off++];
        final pa = <String>[];
        for (var j = 0; j < paCount; j++) {
          if (off >= p.length) return null;
          final al = p[off++];
          if (off + al > p.length) return null;
          pa.add(utf8.decode(p.sublist(off, off + al), allowMalformed: true));
          off += al;
        }
        peers.add(SeedPeer(nodeIdHex: pId, addresses: pa));
      }

      return ContactSeed(
        nodeIdHex: userId,
        displayName: name,
        ownAddresses: addrs,
        seedPeers: peers,
        channelTag: channelTag,
        deviceIdHex: hasDeviceId ? deviceId : null,
        deviceX25519Pk: allZeroDxk ? null : dxk,
        deviceMlKemPk: allZeroDmk ? null : dmk,
      );
    } catch (_) {
      return null;
    }
  }
}

/// A seed peer with node ID and reachable addresses.
class SeedPeer {
  final String nodeIdHex;
  final List<String> addresses; // ip:port pairs

  const SeedPeer({required this.nodeIdHex, this.addresses = const []});
}

// ---------------------------------------------------------------------------
// ContactSeedBuilder — central, stable CR generation (§8.1.1)
//
// Peer-selection, address-computation, and caching live here. The UI never
// assembles a ContactSeed itself — it calls [getContactSeedFor].
// ---------------------------------------------------------------------------

/// Inputs the builder needs from the service layer.
abstract class ContactSeedDataSource {
  List<PeerSummary> get peerSummaries;
  List<String> get localIps;
  String? get publicIp;
  int? get publicPort;
  int get port;
  String get deviceNodeIdHex;
  bool get hasSessionConfirmedPeers;
}

/// Cached network snapshot — the stable half of a ContactSeed.
class _NetworkSnapshot {
  final List<String> ownAddresses;
  final List<SeedPeer> seedPeers;
  final String fingerprint;

  _NetworkSnapshot({
    required this.ownAddresses,
    required this.seedPeers,
    required this.fingerprint,
  });
}

class ContactSeedBuilder {
  final ContactSeedDataSource _source;

  _NetworkSnapshot? _snapshot;
  int? _createdAtMs;

  ContactSeedBuilder(this._source);

  /// True once the network has enough data for a complete CR.
  bool get isReady =>
      _source.hasSessionConfirmedPeers &&
      (_source.publicIp != null || _hasGlobalIpv6 || _hasOnlyLanPeers);

  bool get _hasGlobalIpv6 => _source.localIps.any((ip) =>
      ip.contains(':') && !ip.startsWith('fe80:') &&
      !ip.startsWith('fd') && !ip.startsWith('fc'));

  bool get _hasOnlyLanPeers =>
      _source.peerSummaries.every((p) => _isPrivateIp(p.address));

  /// Build a stable ContactSeed for the given identity.
  /// Returns null if the network isn't ready yet.
  ContactSeed? getContactSeedFor({
    required String nodeIdHex,
    required String displayName,
    required String channelTag,
    Uint8List? userEd25519Pk,
    Uint8List? foundingEd25519Pk,
    Uint8List? deviceX25519Pk,
    Uint8List? deviceMlKemPk,
  }) {
    if (!isReady) return null;
    final snap = _ensureSnapshot();
    return ContactSeed(
      nodeIdHex: nodeIdHex,
      displayName: displayName,
      ownAddresses: snap.ownAddresses,
      seedPeers: snap.seedPeers,
      channelTag: channelTag,
      deviceIdHex: _source.deviceNodeIdHex,
      userEd25519Pk: userEd25519Pk,
      foundingEd25519Pk: foundingEd25519Pk,
      deviceX25519Pk: deviceX25519Pk,
      deviceMlKemPk: deviceMlKemPk,
      createdAtMs: _createdAtMs!,
    );
  }

  /// Force a snapshot rebuild (e.g. after significant network change).
  void invalidate() {
    _snapshot = null;
    _createdAtMs = null;
  }

  _NetworkSnapshot _ensureSnapshot() {
    final fp = _computeFingerprint();
    if (_snapshot != null && _snapshot!.fingerprint == fp) return _snapshot!;
    _snapshot = _buildSnapshot(fp);
    _createdAtMs ??= DateTime.now().millisecondsSinceEpoch;
    return _snapshot!;
  }

  String _computeFingerprint() {
    final sb = StringBuffer();
    sb.write(_source.port);
    sb.write('|');
    for (final ip in _source.localIps) {
      sb.write(ip);
      sb.write(',');
    }
    sb.write('|');
    sb.write(_source.publicIp ?? '');
    sb.write(':');
    sb.write(_source.publicPort ?? 0);
    sb.write('|');
    final valid = _source.peerSummaries
        .where((p) => p.address.isNotEmpty && p.port > 0);
    for (final p in valid) {
      sb.write(p.nodeIdHex.substring(0, 8));
      sb.write('@');
      for (final a in p.allAddresses) {
        sb.write(a);
        sb.write('+');
      }
      sb.write(',');
    }
    return sb.toString();
  }

  _NetworkSnapshot _buildSnapshot(String fp) {
    final validPeers = _source.peerSummaries
        .where((p) => p.address.isNotEmpty && p.port > 0)
        .toList();

    // --- Peer selection ---
    // Sort: most stable first (anchor < stable < normal < volatile),
    // then public-address peers before private-only.
    validPeers.sort((a, b) {
      final tierCmp = a.stabilityTierIndex.compareTo(b.stabilityTierIndex);
      if (tierCmp != 0) return tierCmp;
      final aPub = _hasPublicAddress(a) ? 0 : 1;
      final bPub = _hasPublicAddress(b) ? 0 : 1;
      return aPub.compareTo(bPub);
    });

    final selected = <PeerSummary>[];
    final seenNodeIds = <String>{};

    // Pass 1: Anchor/Stable peers with public address (cold-start priority)
    for (final p in validPeers) {
      if (p.stabilityTierIndex > 1) break; // normal or worse
      if (_hasPublicAddress(p) && seenNodeIds.add(p.nodeIdHex)) {
        selected.add(p);
        if (selected.length >= 3) break;
      }
    }
    // Pass 2: remaining relay-capable peers (public IP / global IPv6)
    for (final p in validPeers) {
      if (selected.length >= 5) break;
      if (_hasPublicAddress(p) && seenNodeIds.add(p.nodeIdHex)) {
        selected.add(p);
      }
    }
    // Pass 3: LAN peers (max 2, dedup by nodeId)
    for (final p in validPeers.where(
        (p) => _isPrivateIp(p.address) && !p.address.contains(':'))) {
      if (selected.length >= 5) break;
      if (!seenNodeIds.add(p.nodeIdHex)) continue;
      selected.add(p);
    }

    final seedPeers = selected.map((p) {
      final sorted = List<String>.from(p.allAddresses);
      sorted.sort((a, b) => _addressPriority(a).compareTo(_addressPriority(b)));
      final top = sorted.isNotEmpty ? sorted.take(3).toList()
          : [_formatAddr(p.address, p.port)];
      // Guarantee global IPv6 inclusion (DS-Lite bypass §4.7)
      if (sorted.length > 3) {
        final gv6 = sorted.firstWhere(
          (a) => a.startsWith('[') &&
              !a.contains('fe80:') && !a.contains('fd') && !a.contains('fc'),
          orElse: () => '',
        );
        if (gv6.isNotEmpty && !top.contains(gv6)) top.add(gv6);
      }
      return SeedPeer(nodeIdHex: p.nodeIdHex, addresses: top);
    }).toList();

    // --- Own addresses ---
    final ownAddrs = <String>[];
    // Up to 2 private IPv4
    final ipv4 = _source.localIps.where((ip) => !ip.contains(':')).take(2);
    for (final ip in ipv4) {
      ownAddrs.add(_formatAddr(ip, _source.port));
    }
    // Public IPv4
    if (_source.publicIp != null && _source.publicPort != null) {
      ownAddrs.add(_formatAddr(_source.publicIp!, _source.publicPort!));
    }
    // First global IPv6 (DS-Lite bypass)
    final gv6 = _source.localIps.firstWhere(
      (ip) => ip.contains(':') && !ip.startsWith('fe80:') &&
              !ip.startsWith('fd') && !ip.startsWith('fc'),
      orElse: () => '',
    );
    if (gv6.isNotEmpty) ownAddrs.add(_formatAddr(gv6, _source.port));

    return _NetworkSnapshot(
      ownAddresses: ownAddrs,
      seedPeers: seedPeers,
      fingerprint: fp,
    );
  }

  // --- Helpers (shared, no longer duplicated in UI) ---

  static bool _hasPublicAddress(PeerSummary p) {
    return p.allAddresses.any((a) {
      if (a.startsWith('[')) {
        final ip = a.substring(1, a.indexOf(']'));
        return !ip.startsWith('fe80:') && !ip.startsWith('fd') && !ip.startsWith('fc');
      }
      final ip = a.split(':').first;
      return !_isPrivateIp(ip);
    });
  }

  static bool _isPrivateIp(String ip) {
    if (ip.contains(':')) {
      final lower = ip.toLowerCase();
      return lower.startsWith('fe80:') || lower.startsWith('fc') ||
             lower.startsWith('fd') || lower == '::1';
    }
    if (ip.startsWith('10.')) return true;
    if (ip.startsWith('192.168.')) return true;
    if (ip.startsWith('172.')) {
      final second = int.tryParse(ip.split('.')[1]);
      if (second != null && second >= 16 && second <= 31) return true;
    }
    if (ip.startsWith('192.0.0.')) return true;
    if (ip.startsWith('100.')) {
      final second = int.tryParse(ip.split('.')[1]) ?? 0;
      if (second >= 64 && second <= 127) return true;
    }
    if (ip.startsWith('127.')) return true;
    return false;
  }

  static String _formatAddr(String ip, int port) =>
      ip.contains(':') ? '[$ip]:$port' : '$ip:$port';

  static int _addressPriority(String addrPort) {
    var host = addrPort;
    if (host.startsWith('[')) {
      final end = host.indexOf(']');
      if (end > 0) host = host.substring(1, end);
    } else {
      final colon = host.lastIndexOf(':');
      if (colon > 0) host = host.substring(0, colon);
    }
    if (host.contains(':')) {
      final lower = host.toLowerCase();
      if (lower.startsWith('fe80') || lower.startsWith('fd') || lower.startsWith('fc')) return 2;
      return 0;
    }
    if (_isPrivateIp(host)) return 2;
    return 0;
  }
}
