/// Higher-level service for creating and managing invite links (§19.6.4).
///
/// Bridges the [InviteLink] model (URL generation/parsing, per-platform
/// Ed25519 signature verification) with the running node's state (public
/// addresses, current version, binary hashes/signatures from the
/// UpdateManifest), and manages invite-scoped Nostr binary-availability
/// records (§19.6.5) so the invited user can discover binary sources even
/// after the inviter's IP changes.
///
/// No maintainer secret key required at runtime — the per-platform
/// signatures travel through the signed UpdateManifest from the release
/// build to every node.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/crypto/secp256k1_schnorr.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/peer_info.dart' show PeerAddress, bytesToHex;
import 'package:cleona/core/network/rendezvous/binary_rendezvous_manager.dart';
import 'package:cleona/core/network/rendezvous/nostr_provider.dart';
import 'package:cleona/core/network/rendezvous/rendezvous_provider.dart';
import 'package:cleona/core/network/rendezvous/rendezvous_secret.dart';
import 'package:cleona/core/update/invite_link.dart';

/// Salt for deriving the invite-scoped Nostr lookup tag (§19.6.5). Distinct
/// from [deriveInviteBinaryKey]'s salt (`cleona-invite-binary-v1`) so tag and
/// encryption key are independent HKDF outputs of the same nonce.
const String _inviteBinaryTagSalt = 'cleona-invite-binary-tag-v1';

/// TTL hint (content-embedded) for invite-scoped binary records. The invited
/// device does not yet hold the network_secret, so these records live in a
/// separate, short-lived namespace rather than the network-wide one.
const Duration kInviteBinaryTtl = Duration(hours: 72);

/// Higher-level service for creating invite links (§19.6.4).
///
/// Coordinates between the running node's state (addresses, version,
/// binary hashes/signatures from the manifest) to produce ready-to-share
/// invite links. Also manages invite-scoped Nostr records (§19.6.5)
/// so that the invited user can discover binary sources even after the
/// inviter's IP changes.
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
    );

    _log.info('Invite link created: address=${address.ip}:${address.port} '
        'version=$currentVersion platforms=${binaryHashes.keys.join(",")}');

    return link.toUrl();
  }

  /// Publish an invite-scoped binary availability record on Nostr (§19.6.5).
  ///
  /// The invited user (Bob) doesn't have the network_secret yet, so the
  /// record is encrypted with an invite_binary_key derived from a nonce
  /// embedded in the invite link. TTL: 72h.
  ///
  /// [networkSecret] — for deriving the invite binary key
  /// [inviteNonce] — unique nonce for this invite (e.g., first 16 bytes of contactSeed)
  /// [record] — the binary availability record to publish
  /// [providers] — Nostr relay providers
  Future<void> publishInviteScopedRecord({
    required Uint8List networkSecret,
    required String inviteNonce,
    required BinaryAvailabilityRecord record,
    required List<RendezvousProvider> providers,
    required Uint8List deviceId,
  }) async {
    final inviteBinaryKey = deriveInviteBinaryKey(
        networkSecret, Uint8List.fromList(utf8.encode(inviteNonce)));
    final tag = _computeInviteTag(inviteNonce);

    final encrypted = encryptBinaryRecord(record, inviteBinaryKey, tag);
    final nostrSk = deriveBinaryNostrSecretKey(networkSecret, deviceId);
    final nostrKp = secp256k1KeypairFromSecret(nostrSk);

    var publishCount = 0;
    for (final provider in providers) {
      if (!provider.isAvailable) continue;
      try {
        if (provider is NostrProvider) {
          await provider.publishWithKey(tag, encrypted, nostrKp.secretKey);
        } else {
          await provider.publish(tag, encrypted);
        }
        publishCount++;
      } catch (e) {
        _log.debug('Invite-scoped binary publish failed: $e');
      }
    }

    _log.info('Invite-scoped binary record published to $publishCount '
        'provider(s), TTL=${kInviteBinaryTtl.inHours}h, '
        'platform=${record.platform}');
  }

  /// Resolve invite-scoped records (called by Bob after clicking invite link).
  ///
  /// [inviteBinaryKey] — derived from the invite link parameters
  /// [inviteNonce] — from the invite link
  /// [providers] — Nostr relay providers
  Future<List<ResolvedBinaryEndpoint>> resolveInviteScopedRecords({
    required Uint8List inviteBinaryKey,
    required String inviteNonce,
    required List<RendezvousProvider> providers,
  }) async {
    final tag = _computeInviteTag(inviteNonce);
    final results = <ResolvedBinaryEndpoint>[];
    final seenDevices = <String>{};

    final records = await Future.wait(providers
        .where((p) => p.isAvailable)
        .map((p) => p.resolve(tag).catchError((_) => null)));

    for (final signed in records) {
      if (signed == null) continue;
      final rec = decryptBinaryRecord(signed, inviteBinaryKey, tag);
      if (rec == null || rec.addresses.isEmpty) continue;
      final devHex = bytesToHex(rec.deviceId);
      if (seenDevices.contains(devHex)) continue;
      seenDevices.add(devHex);
      results.add(ResolvedBinaryEndpoint(
        addresses: rec.addresses,
        deviceIdHex: devHex,
        platform: rec.platform,
        version: rec.version,
        binaryHash: rec.binaryHash,
        hasFullBinary: rec.hasFullBinary,
        fragmentIndices: rec.fragmentIndices,
        seq: rec.seq,
      ));
    }

    _log.info('Invite-scoped binary resolve: ${results.length} endpoint(s) '
        'found');
    return results;
  }

  /// Derives the invite-scoped Nostr lookup tag from the invite nonce.
  /// HKDF-SHA-256, salt=[_inviteBinaryTagSalt], info=inviteNonce, length=32.
  static Uint8List _computeInviteTag(String inviteNonce) {
    return SodiumFFI().hkdfSha256(
      Uint8List.fromList(utf8.encode(inviteNonce)),
      salt: Uint8List.fromList(utf8.encode(_inviteBinaryTagSalt)),
      info: Uint8List.fromList(utf8.encode(inviteNonce)),
      length: 32,
    );
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
