import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/network/peer_info.dart' show hexToBytes;
import 'package:cleona/core/update/update_manifest.dart' show UpdateChecker;

/// Invite link for initial installation (§19.6.4): bootstraps a fresh device
/// with both the P2P ContactSeed and a maintainer-signed binary hash map, so
/// the recipient can verify a binary obtained via any distribution channel
/// (in-network download, physical transfer, fallback URL) without trusting
/// the channel itself.
///
/// All parameters live in the URL hash fragment (`#...`), never the query
/// string — the fragment is not sent to any server, preserving the same
/// privacy property as OAuth implicit-flow tokens.
class InviteLink {
  static const String _path = '/cleona';

  final String nodeIp;
  final int nodePort;
  final String contactSeed;
  final Map<String, String> binaryHashes;
  final Uint8List maintainerSignature;
  final String version;
  final String? fallbackUrl;

  const InviteLink({
    required this.nodeIp,
    required this.nodePort,
    required this.contactSeed,
    required this.binaryHashes,
    required this.maintainerSignature,
    required this.version,
    this.fallbackUrl,
  });

  /// Deterministic payload signed by the maintainer key: sorted
  /// `platform:hash` lines, then the version, newline-separated.
  static String _hashMapPayload(Map<String, String> hashes, String version) {
    final platforms = hashes.keys.toList()..sort();
    final lines = platforms.map((p) => '$p:${hashes[p]}').join('\n');
    return '$lines\n$version';
  }

  String _payload() => _hashMapPayload(binaryHashes, version);

  /// Generate the full invite link URL.
  String toUrl() {
    final host = nodeIp.contains(':') ? '[$nodeIp]' : nodeIp;
    final hJson = jsonEncode(binaryHashes);
    final hParam = base64.encode(utf8.encode(hJson));
    final mParam = base64.encode(maintainerSignature);

    final frag = StringBuffer();
    frag.write('s=${Uri.encodeComponent(contactSeed)}');
    frag.write('&h=${Uri.encodeComponent(hParam)}');
    frag.write('&m=${Uri.encodeComponent(mParam)}');
    frag.write('&v=${Uri.encodeComponent(version)}');
    if (fallbackUrl != null && fallbackUrl!.isNotEmpty) {
      frag.write('&f=${Uri.encodeComponent(fallbackUrl!)}');
    }

    return 'http://$host:$nodePort$_path#$frag';
  }

  /// Parse an invite link URL. Returns null if invalid.
  static InviteLink? fromUrl(String url) {
    try {
      final hashIdx = url.indexOf('#');
      if (hashIdx < 0) return null;
      final beforeHash = url.substring(0, hashIdx);
      final fragment = url.substring(hashIdx + 1);

      final uri = Uri.parse(beforeHash);
      final host = uri.host;
      if (host.isEmpty) return null;
      final port = uri.hasPort ? uri.port : 80;

      final params = <String, String>{};
      for (final part in fragment.split('&')) {
        final eqIdx = part.indexOf('=');
        if (eqIdx < 0) continue;
        final key = part.substring(0, eqIdx);
        final rawValue = part.substring(eqIdx + 1);
        try {
          params[key] = Uri.decodeComponent(rawValue);
        } catch (_) {
          params[key] = rawValue;
        }
      }

      final seed = params['s'];
      final hParam = params['h'];
      final mParam = params['m'];
      final version = params['v'];
      if (seed == null || hParam == null || mParam == null || version == null) {
        return null;
      }

      final hJson = utf8.decode(base64.decode(hParam));
      final decodedMap = jsonDecode(hJson) as Map<String, dynamic>;
      final hashes = decodedMap.map((k, v) => MapEntry(k, v as String));

      final signature = base64.decode(mParam);

      return InviteLink(
        nodeIp: host,
        nodePort: port,
        contactSeed: seed,
        binaryHashes: hashes,
        maintainerSignature: Uint8List.fromList(signature),
        version: version,
        fallbackUrl: params['f'],
      );
    } catch (_) {
      return null;
    }
  }

  /// Verify the maintainer signature over the hash map + version.
  bool verifySignature() {
    try {
      final payload = Uint8List.fromList(utf8.encode(_payload()));
      final pubKey = hexToBytes(UpdateChecker.maintainerPublicKeyHex);
      return SodiumFFI().verifyEd25519(payload, maintainerSignature, pubKey);
    } catch (_) {
      return false;
    }
  }

  /// Get the expected hash for a specific platform.
  String? hashForPlatform(String platform) => binaryHashes[platform];
}

/// Creates maintainer-signed invite links (§19.6.4). Only the maintainer
/// holds the Ed25519 secret key needed to call [create].
class InviteLinkGenerator {
  static InviteLink create({
    required Uint8List maintainerSk,
    required String contactSeed,
    required String nodeIp,
    required int nodePort,
    required Map<String, String> binaryHashes,
    required String version,
    String? fallbackUrl,
  }) {
    final payload = InviteLink._hashMapPayload(binaryHashes, version);
    final signature = SodiumFFI().signEd25519(
      Uint8List.fromList(utf8.encode(payload)),
      maintainerSk,
    );
    return InviteLink(
      nodeIp: nodeIp,
      nodePort: nodePort,
      contactSeed: contactSeed,
      binaryHashes: binaryHashes,
      maintainerSignature: signature,
      version: version,
      fallbackUrl: fallbackUrl,
    );
  }
}
