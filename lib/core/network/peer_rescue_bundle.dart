import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/crypto/network_secret.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/network/compression.dart';
import 'package:cleona/core/network/peer_info.dart' show bytesToHex;

/// Result of [PeerRescueBundle.parseAndValidate] / [PeerRescueBundle.parseUriAndValidate].
///
/// [bundle] is non-null only when [networkTagValid] is true (HMAC passes).
/// [sigValid] is true when the exporter's Ed25519 sig also verified.
/// [sigUnknownExporter] is true when HMAC passed but we have no Ed25519 key
/// for the exporter (HMAC-only trust).
/// [ageHours] is how old the bundle is in fractional hours (from [bundle.createdAt]).
class PeerRescueBundleParseResult {
  final PeerRescueBundle? bundle;
  final bool networkTagValid;
  final bool sigValid;
  final bool sigUnknownExporter;
  final double ageHours;
  final String? errorMessage;

  const PeerRescueBundleParseResult({
    this.bundle,
    required this.networkTagValid,
    this.sigValid = false,
    this.sigUnknownExporter = false,
    this.ageHours = 0,
    this.errorMessage,
  });

  bool get ok => networkTagValid;
}

/// Peer Rescue Bundle — Architecture §8.1.2
///
/// A static, human-carried artefact encoding up to ~10 reachable peers
/// so that a node that lost all connectivity can re-enter the network
/// out-of-band (e-mail, messenger, USB stick …).
///
/// Wire format (format byte 0x05 = zstd, 0x06 = uncompressed):
/// ```
/// [1B format]
/// [1B version]            — currently 0x01
/// [8B createdAtMs]        — big-endian uint64
/// [1B channel]            — 'b'=0x62 live='l'=0x6C
/// [32B exporterDeviceId]
/// [1B peerCount]
/// foreach peer:
///   [32B peerNodeId]
///   [1B addrCount]
///   foreach addr:
///     [1B len, addrUTF8]
/// [64B exporterEd25519Sig] — over all preceding bytes (after format byte)
/// [32B networkTag]         — HMAC-SHA256(networkSecret, all preceding bytes)
/// ```
///
/// Validation order: (1) networkTag HMAC (rejects foreign-network bundles);
/// (2) exporterEd25519Sig — if exporter is known contact, full provenance;
/// otherwise HMAC-only trust; (3) age from createdAtMs shown to the UI.
///
/// BOUNDARIES: no MessageType, no DHT publish, no auto-retry, no network
/// requests of any kind — purely a serialization / deserialization helper.
class PeerRescueBundle {
  static const int currentVersion = 0x01;

  /// Wire format byte for zstd-compressed bundle.
  static const int formatZstd = 0x05;

  /// Wire format byte for uncompressed bundle.
  static const int formatUncompressed = 0x06;

  /// URI scheme prefix for rescue bundles.
  static const String uriPrefix = 'cleona://reconnect?b=';

  /// Maximum peers encoded in a single bundle.
  static const int maxPeers = 10;

  /// Ed25519 signature length in bytes.
  static const int sigLength = 64;

  /// Network tag (HMAC-SHA256) length in bytes.
  static const int networkTagLength = 32;

  // ── Bundle fields ──────────────────────────────────────────────────────────

  final int version;
  final DateTime createdAt;
  final String channelTag; // 'b' or 'l'
  final Uint8List exporterDeviceId; // 32 bytes
  final List<RescuePeer> peers;
  final Uint8List exporterSig; // 64 bytes — over payload (before networkTag)
  final Uint8List networkTag;  // 32 bytes — HMAC over everything before it

  PeerRescueBundle({
    required this.version,
    required this.createdAt,
    required this.channelTag,
    required this.exporterDeviceId,
    required this.peers,
    required this.exporterSig,
    required this.networkTag,
  });

  // ── Serialization ──────────────────────────────────────────────────────────

  /// Build the binary payload body (everything after the format byte, before
  /// the networkTag). When [existingSig] is provided it is appended, enabling
  /// the HMAC to cover it.
  static Uint8List _buildPayload({
    required int version,
    required DateTime createdAt,
    required String channelTag,
    required Uint8List exporterDeviceId,
    required List<RescuePeer> peers,
    Uint8List? existingSig,
  }) {
    final bb = BytesBuilder(copy: false);

    bb.addByte(version);

    // createdAtMs — big-endian uint64
    final ms = createdAt.millisecondsSinceEpoch;
    for (var i = 7; i >= 0; i--) {
      bb.addByte((ms >> (i * 8)) & 0xFF);
    }

    // channel
    bb.addByte(channelTag == 'l' ? 0x6C : 0x62);

    // exporterDeviceId (32 bytes)
    bb.add(exporterDeviceId);

    // peers
    final capped = peers.take(maxPeers).toList();
    bb.addByte(capped.length);
    for (final p in capped) {
      bb.add(p.nodeId);
      final cappedAddrs = p.addresses.take(255).toList();
      bb.addByte(cappedAddrs.length);
      for (final a in cappedAddrs) {
        final ab = utf8.encode(a);
        final al = ab.length.clamp(0, 255);
        bb.addByte(al);
        bb.add(ab.sublist(0, al));
      }
    }

    if (existingSig != null) {
      bb.add(existingSig);
    }

    return bb.toBytes();
  }

  /// Serialize to bytes (tries zstd, falls back to uncompressed).
  Uint8List toBytes() {
    final payload = _buildPayload(
      version: version,
      createdAt: createdAt,
      channelTag: channelTag,
      exporterDeviceId: exporterDeviceId,
      peers: peers,
      existingSig: exporterSig,
    );

    // Append networkTag after the sig
    final full = Uint8List(payload.length + networkTag.length);
    full.setAll(0, payload);
    full.setAll(payload.length, networkTag);

    try {
      final compressed = ZstdCompression.instance.compress(
          Uint8List.fromList(full), level: 3);
      if (compressed.length < full.length) {
        final out = BytesBuilder(copy: false);
        out.addByte(formatZstd);
        out.add(compressed);
        return out.toBytes();
      }
    } catch (_) {}

    final out = BytesBuilder(copy: false);
    out.addByte(formatUncompressed);
    out.add(full);
    return out.toBytes();
  }

  /// Encode as URI for QR codes / sharing.
  String toUri() {
    final bytes = toBytes();
    return '$uriPrefix${base64Url.encode(bytes)}';
  }

  // ── Construction (signed) ──────────────────────────────────────────────────

  /// Build and sign a bundle from the given peers.
  /// [exporterDeviceId] must be 32 bytes; [exporterEd25519Sk] must be 64 bytes.
  static PeerRescueBundle build({
    required Uint8List exporterDeviceId,
    required Uint8List exporterEd25519Sk,
    required List<RescuePeer> peers,
    String? channelTag,
  }) {
    final ch = channelTag ??
        (NetworkSecret.channel == NetworkChannel.live ? 'l' : 'b');
    final now = DateTime.now();

    // 1. Build payload WITHOUT sig to sign it
    final unsigned = _buildPayload(
      version: currentVersion,
      createdAt: now,
      channelTag: ch,
      exporterDeviceId: exporterDeviceId,
      peers: peers,
    );

    // 2. Sign with Ed25519
    final sodium = SodiumFFI();
    final sig = sodium.signEd25519(unsigned, exporterEd25519Sk);

    // 3. Build payload WITH sig, then HMAC over it
    final withSig = _buildPayload(
      version: currentVersion,
      createdAt: now,
      channelTag: ch,
      exporterDeviceId: exporterDeviceId,
      peers: peers,
      existingSig: sig,
    );

    // 4. Compute 32-byte HMAC-SHA256 using the network secret
    final tag = _computeNetworkTag(withSig);

    return PeerRescueBundle(
      version: currentVersion,
      createdAt: now,
      channelTag: ch,
      exporterDeviceId: exporterDeviceId,
      peers: peers,
      exporterSig: sig,
      networkTag: tag,
    );
  }

  // ── Parsing & Validation ───────────────────────────────────────────────────

  /// Parse bytes and validate.
  /// [knownExporterEd25519Pk] — if the caller can supply the exporter's
  /// Ed25519 public key (because the exporter is a known contact), full
  /// provenance is verified. Pass null for HMAC-only validation.
  static PeerRescueBundleParseResult parseAndValidate(
    Uint8List bytes, {
    Uint8List? knownExporterEd25519Pk,
  }) {
    if (bytes.length < 2) {
      return const PeerRescueBundleParseResult(
          networkTagValid: false,
          errorMessage: 'Bundle too short');
    }

    final format = bytes[0];
    Uint8List payload;
    if (format == formatZstd) {
      try {
        payload = ZstdCompression.instance.decompress(
            Uint8List.sublistView(bytes, 1));
      } catch (e) {
        return PeerRescueBundleParseResult(
            networkTagValid: false,
            errorMessage: 'Decompression failed: $e');
      }
    } else if (format == formatUncompressed) {
      payload = Uint8List.sublistView(bytes, 1);
    } else {
      return PeerRescueBundleParseResult(
          networkTagValid: false,
          errorMessage: 'Unknown bundle format: 0x${format.toRadixString(16)}');
    }

    return _parsePayload(payload, knownExporterEd25519Pk: knownExporterEd25519Pk);
  }

  /// Parse a URI string (`cleona://reconnect?b=<base64url>`).
  static PeerRescueBundleParseResult parseUriAndValidate(
    String uri, {
    Uint8List? knownExporterEd25519Pk,
  }) {
    try {
      if (!uri.startsWith(uriPrefix)) {
        return const PeerRescueBundleParseResult(
            networkTagValid: false,
            errorMessage: 'Not a rescue bundle URI');
      }
      final b64 = uri.substring(uriPrefix.length);
      final bytes = base64Url.decode(b64);
      return parseAndValidate(bytes, knownExporterEd25519Pk: knownExporterEd25519Pk);
    } catch (e) {
      return PeerRescueBundleParseResult(
          networkTagValid: false,
          errorMessage: 'URI parse error: $e');
    }
  }

  static PeerRescueBundleParseResult _parsePayload(
    Uint8List p, {
    Uint8List? knownExporterEd25519Pk,
  }) {
    // Minimum: 1(ver) + 8(ms) + 1(ch) + 32(deviceId) + 1(peerCount) +
    //          sigLength(64) + networkTagLength(32) = 139 bytes
    if (p.length < 139) {
      return const PeerRescueBundleParseResult(
          networkTagValid: false,
          errorMessage: 'Bundle payload too short');
    }

    try {
      // --- Split off networkTag (last 32 bytes) ---
      final withSig = Uint8List.sublistView(p, 0, p.length - networkTagLength);
      final tagBytes = Uint8List.sublistView(p, p.length - networkTagLength);

      // (1) Validate HMAC / network tag — rejects foreign-network bundles
      final expectedTag = _computeNetworkTag(withSig);
      if (!_ctEquals(tagBytes, expectedTag)) {
        return const PeerRescueBundleParseResult(
            networkTagValid: false,
            errorMessage: 'Network tag mismatch — bundle from wrong network or corrupted');
      }

      // --- Parse body ---
      // withSig layout: payload_body (variable) + 64B sig
      if (withSig.length < sigLength + 1) {
        return const PeerRescueBundleParseResult(
            networkTagValid: true,
            errorMessage: 'Bundle body too short after tag strip');
      }
      final sigData = Uint8List.sublistView(withSig, withSig.length - sigLength);
      final body = Uint8List.sublistView(withSig, 0, withSig.length - sigLength);

      var off = 0;

      // version
      final version = body[off++];

      // createdAtMs — big-endian uint64
      if (off + 8 > body.length) {
        return const PeerRescueBundleParseResult(
            networkTagValid: true,
            errorMessage: 'Truncated at createdAtMs');
      }
      var ms = 0;
      for (var i = 0; i < 8; i++) {
        ms = (ms << 8) | body[off++];
      }
      final createdAt = DateTime.fromMillisecondsSinceEpoch(ms);

      // channel
      if (off >= body.length) {
        return const PeerRescueBundleParseResult(
            networkTagValid: true,
            errorMessage: 'Truncated at channel byte');
      }
      final chByte = body[off++];
      final channelTag = chByte == 0x6C ? 'l' : 'b';

      // exporterDeviceId
      if (off + 32 > body.length) {
        return const PeerRescueBundleParseResult(
            networkTagValid: true,
            errorMessage: 'Truncated at exporterDeviceId');
      }
      final exporterDeviceId = Uint8List.fromList(body.sublist(off, off + 32));
      off += 32;

      // peers
      if (off >= body.length) {
        return const PeerRescueBundleParseResult(
            networkTagValid: true,
            errorMessage: 'Truncated at peerCount');
      }
      final peerCount = body[off++];
      final peers = <RescuePeer>[];
      for (var i = 0; i < peerCount; i++) {
        if (off + 32 > body.length) {
          return PeerRescueBundleParseResult(
              networkTagValid: true,
              errorMessage: 'Truncated at peer nodeId $i');
        }
        final nodeId = Uint8List.fromList(body.sublist(off, off + 32));
        off += 32;
        if (off >= body.length) {
          return PeerRescueBundleParseResult(
              networkTagValid: true,
              errorMessage: 'Truncated at addrCount for peer $i');
        }
        final addrCount = body[off++];
        final addrs = <String>[];
        for (var j = 0; j < addrCount; j++) {
          if (off >= body.length) {
            return PeerRescueBundleParseResult(
                networkTagValid: true,
                errorMessage: 'Truncated at addr len peer $i addr $j');
          }
          final al = body[off++];
          if (off + al > body.length) {
            return PeerRescueBundleParseResult(
                networkTagValid: true,
                errorMessage: 'Truncated at addr data peer $i addr $j');
          }
          addrs.add(utf8.decode(body.sublist(off, off + al),
              allowMalformed: true));
          off += al;
        }
        peers.add(RescuePeer(nodeId: nodeId, addresses: addrs));
      }

      // (2) Verify Ed25519 sig if caller supplied exporter pubkey
      bool sigValid = false;
      bool sigUnknownExporter = false;
      if (knownExporterEd25519Pk != null &&
          knownExporterEd25519Pk.length == 32) {
        try {
          final sodium = SodiumFFI();
          sigValid = sodium.verifyEd25519(body, sigData, knownExporterEd25519Pk);
        } catch (_) {
          sigValid = false;
        }
      } else {
        sigUnknownExporter = true;
      }

      // (3) Age
      final ageHours =
          DateTime.now().difference(createdAt).inSeconds / 3600.0;

      final bundle = PeerRescueBundle(
        version: version,
        createdAt: createdAt,
        channelTag: channelTag,
        exporterDeviceId: exporterDeviceId,
        peers: peers,
        exporterSig: sigData,
        networkTag: tagBytes,
      );

      return PeerRescueBundleParseResult(
        bundle: bundle,
        networkTagValid: true,
        sigValid: sigValid,
        sigUnknownExporter: sigUnknownExporter,
        ageHours: ageHours,
      );
    } catch (e) {
      return PeerRescueBundleParseResult(
          networkTagValid: false,
          errorMessage: 'Parse error: $e');
    }
  }

  // ── Internal helpers ───────────────────────────────────────────────────────

  /// Compute 32-byte HMAC-SHA256 with the network secret over [data].
  /// Uses the same key-padding as NetworkSecret (16-byte secret → 32-byte key).
  static Uint8List _computeNetworkTag(Uint8List data) {
    final sodium = SodiumFFI();
    final secret = NetworkSecret.secret; // 16 bytes
    final key = Uint8List(32);
    key.setRange(0, 16, secret);
    return Uint8List.fromList(sodium.hmacSha256(key, data));
  }

  /// Constant-time equality for equal-length Uint8Lists.
  static bool _ctEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

/// A peer entry inside a [PeerRescueBundle].
class RescuePeer {
  /// 32-byte raw node ID.
  final Uint8List nodeId;

  /// All known addresses as "ip:port" or "[ipv6]:port" strings.
  final List<String> addresses;

  const RescuePeer({required this.nodeId, this.addresses = const []});

  String get nodeIdHex => bytesToHex(nodeId);

  Map<String, dynamic> toJson() => {
        'nodeIdHex': nodeIdHex,
        'addresses': addresses,
      };
}
