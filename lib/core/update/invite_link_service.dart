/// Higher-level service for creating and managing invite links (§19.6.4).
///
/// Bridges the [InviteLink] model (URL generation/parsing, per-platform
/// Ed25519 signature verification) with the running node's state (public
/// addresses, current version, binary hashes/signatures from the
/// UpdateManifest).
///
/// No maintainer secret key required at runtime — the per-platform
/// signatures travel through the signed UpdateManifest from the release
/// build to every node.
library;


import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/peer_info.dart' show PeerAddress;
import 'package:cleona/core/network/rendezvous/rendezvous_provider.dart';
import 'package:cleona/core/update/invite_link.dart';

/// Higher-level service for creating invite links (§19.6.4).
///
/// Coordinates between the running node's state (addresses, version,
/// binary hashes/signatures from the manifest) to produce ready-to-share
/// invite links.
class InviteLinkService {
  final CLogger _log;

  InviteLinkService({String? profileDir})
      : _log = CLogger.get('invite-link', profileDir: profileDir);

  /// Generate an invite link using the current node state.
  ///
  /// [contactSeed] — the ContactSeed to embed (existing §8.1.1 mechanism).
  /// [nodeAddresses] — current node's public addresses (IP:port pairs).
  /// [currentVersion] — app version string.
  /// [binaryHashes] — per-platform SHA-256 hashes from the UpdateManifest.
  /// [binarySignatures] — per-platform Ed25519 signatures from the manifest.
  /// [fallbackUrl] — optional external download URL (e.g., GitHub Release).
  String createInviteLink({
    required String contactSeed,
    required List<EndpointAddress> nodeAddresses,
    required String currentVersion,
    required Map<String, String> binaryHashes,
    required Map<String, String> binarySignatures,
    String? fallbackUrl,
    Map<String, int>? binarySizes,
  }) {
    final address = bestPublicAddress(nodeAddresses);
    if (address == null) {
      throw StateError(
          'createInviteLink: no public address available among '
          '${nodeAddresses.length} candidate(s)');
    }

    final link = InviteLink(
      nodeIp: address.ip,
      nodePort: address.port,
      contactSeed: contactSeed,
      binaryHashes: binaryHashes,
      binarySignatures: binarySignatures,
      version: currentVersion,
      fallbackUrl: fallbackUrl,
      binarySizes: binarySizes,
    );

    _log.info('Invite link created: address=${address.ip}:${address.port} '
        'version=$currentVersion platforms=${binaryHashes.keys.join(",")}');

    return link.toUrl();
  }

  /// Pick the best public address from a list.
  /// Prefers: public IPv4 > global IPv6 > private (returns null if no public).
  static EndpointAddress? bestPublicAddress(List<EndpointAddress> addresses) {
    EndpointAddress? bestV4;
    EndpointAddress? bestV6;

    for (final addr in addresses) {
      if (PeerAddress.isPrivateIp(addr.ip)) continue;
      if (addr.ip.contains(':')) {
        bestV6 ??= addr;
      } else {
        bestV4 ??= addr;
      }
    }

    return bestV4 ?? bestV6;
  }

  void dispose() {
    // No owned resources (providers are owned by the caller).
  }
}
