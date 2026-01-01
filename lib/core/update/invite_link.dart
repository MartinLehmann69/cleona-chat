import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/network/peer_info.dart' show hexToBytes;
import 'package:cleona/core/update/update_manifest.dart' show UpdateChecker;

/// Invite link for initial installation (§19.6.4): bootstraps a fresh device
/// with both the P2P ContactSeed and maintainer-signed per-platform binary
/// hashes, so the recipient can verify a binary obtained via any distribution
/// channel (in-network download, physical transfer, fallback URL) without
/// trusting the channel itself.
///
/// Uses the same per-platform Ed25519 signatures as the UpdateManifest
/// (`binarySignatures`): each signature covers the raw 32-byte SHA-256 hash
/// of that platform's binary. No separate signing step required — the
/// signatures are produced once at release time and travel through the
/// manifest to every node.
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
  final Map<String, String> binarySignatures;
  final String version;
  final String? fallbackUrl;

  const InviteLink({
    required this.nodeIp,
    required this.nodePort,
    required this.contactSeed,
    required this.binaryHashes,
    required this.binarySignatures,
    required this.version,
    this.fallbackUrl,
  });

  /// Generate the full invite link URL.
  String toUrl() {
    final host = nodeIp.contains(':') ? '[$nodeIp]' : nodeIp;
    final hParam = base64.encode(utf8.encode(jsonEncode(binaryHashes)));
    final mParam = base64.encode(utf8.encode(jsonEncode(binarySignatures)));

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
      if (seed == null || hParam == null || mParam == null ||
          version == null) {
        return null;
      }

      final hJson = utf8.decode(base64.decode(hParam));
      final hashMap = jsonDecode(hJson) as Map<String, dynamic>;
      final hashes = hashMap.map((k, v) => MapEntry(k, v as String));

      final mJson = utf8.decode(base64.decode(mParam));
      final sigMap = jsonDecode(mJson) as Map<String, dynamic>;
      final sigs = sigMap.map((k, v) => MapEntry(k, v as String));

      return InviteLink(
        nodeIp: host,
        nodePort: port,
        contactSeed: seed,
        binaryHashes: hashes,
        binarySignatures: sigs,
        version: version,
        fallbackUrl: params['f'],
      );
    } catch (_) {
      return null;
    }
  }

  /// Verify the maintainer signature for a specific platform.
  bool verifySignatureForPlatform(String platform) {
    try {
      final hashHex = binaryHashes[platform];
      final sigBase64 = binarySignatures[platform];
      if (hashHex == null || sigBase64 == null) return false;

      final hashBytes = hexToBytes(hashHex);
      final sigBytes = base64.decode(sigBase64);
      final pubKey = hexToBytes(UpdateChecker.maintainerPublicKeyHex);
      return SodiumFFI().verifyEd25519(
        Uint8List.fromList(hashBytes),
        Uint8List.fromList(sigBytes),
        pubKey,
      );
    } catch (_) {
      return false;
    }
  }

  /// Get the expected hash for a specific platform.
  String? hashForPlatform(String platform) => binaryHashes[platform];

  /// Get the signature for a specific platform.
  String? signatureForPlatform(String platform) => binarySignatures[platform];
}
