/// Orchestrator for External Rendezvous publish/resolve lifecycle.
///
/// Architecture §4.11.7 (Publish Triggers) + §4.11 integration.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:cleona/core/crypto/secp256k1_schnorr.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/peer_info.dart';
import 'package:cleona/core/network/rendezvous/nostr_provider.dart';
import 'package:cleona/core/network/rendezvous/rendezvous_provider.dart';
import 'package:cleona/core/network/rendezvous/rendezvous_secret.dart';

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

const Duration kRendezvousRefreshInterval = Duration(hours: 4);
const Duration kRendezvousNetworkChangeDebounce = Duration(seconds: 10);

// ---------------------------------------------------------------------------
// Contact descriptor (minimal, no dependency on ContactManager)
// ---------------------------------------------------------------------------

class RendezvousContact {
  final String userIdHex;
  final Uint8List foundingEd25519Pk;

  const RendezvousContact({
    required this.userIdHex,
    required this.foundingEd25519Pk,
  });
}

// ---------------------------------------------------------------------------
// Address descriptor for the current endpoint
// ---------------------------------------------------------------------------

class RendezvousAddress {
  final String ip;
  final int port;

  const RendezvousAddress(this.ip, this.port);
}

// ---------------------------------------------------------------------------
// Resolved endpoint (output of resolve)
// ---------------------------------------------------------------------------

class ResolvedEndpoint {
  final String contactUserIdHex;
  final List<EndpointAddress> addresses;
  final int seq;

  /// Device that published the record (§4.11.11: lets the node map a later
  /// PONG from this device back to the contact for the
  /// contact-endpoint-confirmed outbox edge).
  final String? deviceIdHex;

  const ResolvedEndpoint({
    required this.contactUserIdHex,
    required this.addresses,
    required this.seq,
    this.deviceIdHex,
  });
}

// ---------------------------------------------------------------------------
// RendezvousManager (§4.11.7)
// ---------------------------------------------------------------------------

class RendezvousManager {
  final List<RendezvousProvider> _providers;
  final CLogger _log;

  Uint8List? _ownFoundingSk;
  String? _ownUserIdHex;
  Uint8List? _deviceId;
  List<RendezvousContact> _contacts = [];
  List<RendezvousAddress> Function()? _addressProvider;

  int _seq = 0;
  Timer? _refreshTimer;
  Timer? _debounceTimer;
  bool _disposed = false;

  RendezvousManager({
    List<RendezvousProvider>? providers,
    String? profileDir,
  })  : _providers = providers ?? [NostrProvider(profileDir: profileDir)],
        _log = CLogger.get('rendezvous', profileDir: profileDir);

  /// Initialize with identity and contact data.
  void init({
    required Uint8List ownFoundingSk,
    required String ownUserIdHex,
    required Uint8List deviceId,
    required List<RendezvousContact> contacts,
    required List<RendezvousAddress> Function() addressProvider,
  }) {
    _ownFoundingSk = ownFoundingSk;
    _ownUserIdHex = ownUserIdHex;
    _deviceId = deviceId;
    _contacts = contacts;
    _addressProvider = addressProvider;
  }

  /// Update the contact list (called on contact add/remove).
  void updateContacts(List<RendezvousContact> contacts) {
    _contacts = contacts;
    // §4.11.7: contact add/remove (e.g. contact accept) must republish so the
    // new mutual contact can resolve our current endpoint. Reuse the existing
    // network-change debounce to batch rapid contact updates.
    onNetworkChanged();
  }

  /// Current contact list snapshot (for Tier 3b resolve in discovery cascade).
  List<RendezvousContact> get contactsSnapshot => List.unmodifiable(_contacts);

  // -------------------------------------------------------------------------
  // Publish (§4.11.7)
  // -------------------------------------------------------------------------

  /// Publish current addresses for all contacts on all providers.
  ///
  /// Called on: startup (after discovery-complete), network change (debounced),
  /// periodic refresh (4h), epoch boundary, contact add/remove.
  Future<void> publishForAllContacts() async {
    final sk = _ownFoundingSk;
    final ownId = _ownUserIdHex;
    final devId = _deviceId;
    final addrFn = _addressProvider;
    if (sk == null || ownId == null || devId == null || addrFn == null) return;
    if (_contacts.isEmpty) return;

    final addresses = addrFn();
    final publicAddresses = addresses
        .where((a) => !PeerAddress.isPrivateIp(a.ip))
        .toList();
    if (publicAddresses.isEmpty) {
      _log.debug('Rendezvous publish: no public addresses, skipping');
      return;
    }

    _seq++;
    final now = DateTime.now().toUtc();
    final currentEpoch = currentEpochString();
    final nextEpoch = nextEpochString();

    final deviceIdHex =
        devId.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    final endpointAddresses =
        publicAddresses.map((a) => EndpointAddress(a.ip, a.port)).toList();

    final record = EndpointRecord(
      addresses: endpointAddresses,
      seq: _seq,
      publishedAt: now.millisecondsSinceEpoch,
      deviceId: devId,
    );

    var publishCount = 0;
    for (final contact in _contacts) {
      final secret = derivePairwiseSecret(
        sk, contact.foundingEd25519Pk, ownId, contact.userIdHex);

      final nostrSk = deriveNostrSecretKey(secret, devId);
      final nostrKp = secp256k1KeypairFromSecret(nostrSk);

      for (final epoch in [currentEpoch, nextEpoch]) {
        final tag = computeLookupTag(secret, epoch, deviceIdHex);
        final encrypted = encryptEndpointRecord(record, secret, tag);

        for (final provider in _providers) {
          if (!provider.isAvailable) continue;
          try {
            if (provider is NostrProvider) {
              await provider.publishWithKey(
                  tag, encrypted, nostrKp.secretKey);
            } else {
              await provider.publish(tag, encrypted);
            }
            publishCount++;
          } catch (e) {
            _log.debug('Rendezvous publish failed for '
                '${contact.userIdHex.substring(0, 8)}…: $e');
          }
        }
      }
    }

    _log.info('Rendezvous: published to $publishCount provider-tag pairs '
        'for ${_contacts.length} contacts (seq=$_seq)');
  }

  /// Schedule a debounced publish after network change.
  void onNetworkChanged() {
    if (_disposed) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(kRendezvousNetworkChangeDebounce, () {
      publishForAllContacts();
    });
  }

  /// Start the periodic refresh timer (4h).
  void startPeriodicRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(kRendezvousRefreshInterval, (_) {
      publishForAllContacts();
    });
  }

  // -------------------------------------------------------------------------
  // Resolve (§4.11 Tier 3b)
  // -------------------------------------------------------------------------

  /// Resolve current addresses for the given contacts via all providers.
  ///
  /// For each contact, looks up device IDs from [contactDeviceIds] and queries
  /// device-scoped tags. Falls back to previous epoch if current yields no hit.
  /// Returns the first valid, decryptable record per contact with highest seq.
  Future<List<ResolvedEndpoint>> resolveContacts(
      List<RendezvousContact> contacts,
      {Map<String, List<String>> contactDeviceIds = const {}}) async {
    final sk = _ownFoundingSk;
    final ownId = _ownUserIdHex;
    if (sk == null || ownId == null) return [];
    if (contacts.isEmpty) return [];

    final currentEpoch = currentEpochString();
    final prevEpoch = previousEpochString();
    final results = <ResolvedEndpoint>[];

    await Future.wait(contacts.map((contact) async {
      final secret = derivePairwiseSecret(
          sk, contact.foundingEd25519Pk, ownId, contact.userIdHex);

      final deviceIds = contactDeviceIds[contact.userIdHex] ?? [];
      if (deviceIds.isEmpty) {
        _log.debug('Rendezvous resolve: no cached deviceIds for '
            '${contact.userIdHex.substring(0, 8)}…, skipping');
        return;
      }

      SignedEndpointRecord? bestRecord;
      Uint8List? bestTag;

      for (final devIdHex in deviceIds) {
        for (final epoch in [currentEpoch, prevEpoch]) {
          final tag = computeLookupTag(secret, epoch, devIdHex);

          final records = await Future.wait(_providers
              .where((p) => p.isAvailable)
              .map((p) => p.resolve(tag).catchError((_) => null)));

          for (final record in records) {
            if (record == null) continue;
            final best = bestRecord;
            if (best == null || record.seq > best.seq) {
              bestRecord = record;
              bestTag = tag;
            }
          }
        }
      }

      if (bestRecord != null && bestTag != null) {
        final endpoint = decryptEndpointRecord(bestRecord, secret, bestTag);
        if (endpoint != null && endpoint.addresses.isNotEmpty) {
          results.add(ResolvedEndpoint(
            contactUserIdHex: contact.userIdHex,
            addresses: endpoint.addresses,
            seq: endpoint.seq,
            deviceIdHex: endpoint.deviceId
                .map((b) => b.toRadixString(16).padLeft(2, '0'))
                .join(),
          ));
          _log.info('Rendezvous resolved '
              '${contact.userIdHex.substring(0, 8)}…: '
              '${endpoint.addresses.length} addresses (seq=${endpoint.seq})');
        }
      }
    }));

    return results;
  }

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  void dispose() {
    _disposed = true;
    _refreshTimer?.cancel();
    _debounceTimer?.cancel();
    for (final provider in _providers) {
      if (provider is NostrProvider) provider.dispose();
    }
  }
}
