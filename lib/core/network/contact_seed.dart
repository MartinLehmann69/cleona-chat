import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/network/compression.dart';
import 'package:cleona/core/network/peer_info.dart' show hexToBytes, bytesToHex;

/// ContactSeed: encodes node identity + reachability into a URI for QR codes.
///
/// Two format generations (§8.1.1):
///
/// **v2 (rev3, current)** — compact, base64url, ~350 chars URI / QR Version 8-10:
/// `cleona://<userIdHex>?n=<name>&c=<b|l>&did=<deviceIdHex>&ep=<userEd25519Pk_base64url>&a=<addrs>&s=<seedPeers>`
///
/// **v1 (legacy, still parsed)** — includes full Device-KEM keys:
/// `cleona://<userIdHex>?...&dxk=<deviceX25519Pk_b64>&dmk=<deviceMlKemPk_b64>&...`
///
/// - nodeIdHex: 64-char hex of the user's 32-byte UserID (§8.1.1).
/// - n: display name (URL-encoded)
/// - c: network channel ('b' = beta, 'l' = live)
/// - did: deviceId (64-char hex)
/// - ep (v2): userEd25519Pk, 32 bytes, base64url — trust-anchor for Deferred
///   Key Exchange and DHT record verification. Integrity: SHA-256(networkSecret + ep) == nodeIdHex.
/// - dxk/dmk (v1 legacy): Device-KEM keys inline — parsed but no longer emitted.
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

  /// Device-X25519 public key (v1 legacy). 32 bytes. Present only in legacy
  /// ContactSeeds that carried the full Device-KEM keys inline.
  final Uint8List? deviceX25519Pk;

  /// Device-ML-KEM-768 public key (v1 legacy). 1184 bytes.
  final Uint8List? deviceMlKemPk;

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
  });

  /// Build the URI string for QR code encoding.
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

      // v1 legacy: Device-KEM pubkeys (standard base64). Parsed for backward
      // compat — URIs with dxk+dmk skip the Deferred Key Exchange entirely.
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
  // v2 binary payload:
  //   [32B userId] [32B deviceId] [32B userEd25519Pk]
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
    try {
      final compressed = ZstdCompression.instance.compress(
          Uint8List.fromList(raw), level: 3);
      if (compressed.length < raw.length) {
        final out = BytesBuilder(copy: false);
        out.addByte(0x03); // v2 compressed
        out.add(compressed);
        return out.toBytes();
      }
    } catch (_) {}
    final out = BytesBuilder(copy: false);
    out.addByte(0x04); // v2 uncompressed
    out.add(raw);
    return out.toBytes();
  }

  static ContactSeed? fromQrBytes(Uint8List data) {
    if (data.length < 2) return null;
    final format = data[0];
    Uint8List payload;
    if (format == 0x01 || format == 0x03) {
      try {
        payload = ZstdCompression.instance.decompress(
            Uint8List.sublistView(data, 1));
      } catch (_) { return null; }
    } else if (format == 0x02 || format == 0x04) {
      payload = Uint8List.sublistView(data, 1);
    } else {
      return null;
    }
    final isV2 = format == 0x03 || format == 0x04;
    return isV2 ? _parseBinaryPayloadV2(payload) : _parseBinaryPayload(payload);
  }

  static ContactSeed? _parseBinaryPayloadV2(Uint8List p) {
    // v2: 32+32+32+1+1+1+1 = 100 bytes minimum
    if (p.length < 100) return null;
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
      );
    } catch (_) {
      return null;
    }
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
