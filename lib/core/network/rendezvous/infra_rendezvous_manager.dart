/// Infrastructure Rendezvous Manager (§4.11.9).
///
/// Publishes and resolves network entry-point addresses (bootstrap, any node
/// with a public IP) under a network-wide tag derived from the network secret.
/// No user identity or contacts required — infrastructure daemons participate.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:cleona/core/crypto/secp256k1_schnorr.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/peer_info.dart';
import 'package:cleona/core/network/rendezvous/nostr_provider.dart';
import 'package:cleona/core/network/rendezvous/rendezvous_provider.dart';
import 'package:cleona/core/network/rendezvous/rendezvous_manager.dart'
    show RendezvousAddress;
import 'package:cleona/core/network/rendezvous/rendezvous_secret.dart';

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

const Duration kInfraRefreshInterval = Duration(hours: 4);
const Duration kInfraNetworkChangeDebounce = Duration(seconds: 10);

// ---------------------------------------------------------------------------
// InfraRendezvousManager (§4.11.9)
// ---------------------------------------------------------------------------

class InfraRendezvousManager {
  final List<RendezvousProvider> _providers;
  final CLogger _log;

  Uint8List? _networkSecret;
  Uint8List? _deviceId;
  List<RendezvousAddress> Function()? _addressProvider;

  int _seq = 0;
  Timer? _refreshTimer;
  Timer? _debounceTimer;
  bool _disposed = false;

  InfraRendezvousManager({
    List<RendezvousProvider>? providers,
    String? profileDir,
  })  : _providers = providers ?? [NostrProvider(profileDir: profileDir)],
        _log = CLogger.get('infra-rv', profileDir: profileDir);

  void init({
    required Uint8List networkSecret,
    required Uint8List deviceId,
    required List<RendezvousAddress> Function() addressProvider,
  }) {
    _networkSecret = networkSecret;
    _deviceId = deviceId;
    _addressProvider = addressProvider;
  }

  // -------------------------------------------------------------------------
  // Publish (§4.11.9)
  // -------------------------------------------------------------------------

  Future<void> publish() async {
    final secret = _networkSecret;
    final devId = _deviceId;
    final addrFn = _addressProvider;
    if (secret == null || devId == null || addrFn == null) return;

    final addresses = addrFn();
    final publicAddresses =
        addresses.where((a) => !PeerAddress.isPrivateIp(a.ip)).toList();
    if (publicAddresses.isEmpty) {
      _log.debug('Infra-RV publish: no public addresses, skipping');
      return;
    }

    _seq++;
    final now = DateTime.now().toUtc();
    final currentEpoch = currentEpochString();
    final nextEpoch = nextEpochString();

    final endpointAddresses =
        publicAddresses.map((a) => EndpointAddress(a.ip, a.port)).toList();

    final record = EndpointRecord(
      addresses: endpointAddresses,
      seq: _seq,
      publishedAt: now.millisecondsSinceEpoch,
      deviceId: devId,
    );

    final nostrSk = deriveInfraNostrSecretKey(secret, devId);
    final nostrKp = secp256k1KeypairFromSecret(nostrSk);

    var publishCount = 0;
    for (final epoch in [currentEpoch, nextEpoch]) {
      final tag = computeInfraTag(secret, epoch);
      final key = deriveInfraKey(secret, epoch);
      final encrypted = encryptEndpointRecord(record, key, tag);

      for (final provider in _providers) {
        if (!provider.isAvailable) continue;
        try {
          if (provider is NostrProvider) {
            await provider.publishWithKey(tag, encrypted, nostrKp.secretKey);
          } else {
            await provider.publish(tag, encrypted);
          }
          publishCount++;
        } catch (e) {
          _log.debug('Infra-RV publish failed: $e');
        }
      }
    }

    _log.info('Infra-RV: published to $publishCount provider-epoch pairs '
        '(seq=$_seq, ${publicAddresses.length} public addresses)');
  }

  void onNetworkChanged() {
    if (_disposed) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(kInfraNetworkChangeDebounce, () {
      publish();
    });
  }

  void startPeriodicRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(kInfraRefreshInterval, (_) {
      publish();
    });
  }

  // -------------------------------------------------------------------------
  // Resolve (§4.11.9 — Tier 3b path B)
  // -------------------------------------------------------------------------

  Future<List<ResolvedInfraEndpoint>> resolve() async {
    final secret = _networkSecret;
    if (secret == null) return [];

    final currentEpoch = currentEpochString();
    final prevEpoch = previousEpochString();
    final results = <ResolvedInfraEndpoint>[];
    final seenDevices = <String>{};

    for (final epoch in [currentEpoch, prevEpoch]) {
      final tag = computeInfraTag(secret, epoch);
      final key = deriveInfraKey(secret, epoch);

      final records = await Future.wait(_providers
          .where((p) => p.isAvailable)
          .map((p) => p.resolve(tag).catchError((_) => null)));

      for (final signed in records) {
        if (signed == null) continue;
        final ep = decryptEndpointRecord(signed, key, tag);
        if (ep == null || ep.addresses.isEmpty) continue;
        final devHex = ep.deviceId
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
        if (seenDevices.contains(devHex)) continue;
        seenDevices.add(devHex);
        results.add(ResolvedInfraEndpoint(
          addresses: ep.addresses,
          deviceIdHex: devHex,
          seq: ep.seq,
        ));
      }
    }

    if (results.isNotEmpty) {
      _log.info('Infra-RV: resolved ${results.length} infra node(s)');
    }
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

// ---------------------------------------------------------------------------
// Result type
// ---------------------------------------------------------------------------

class ResolvedInfraEndpoint {
  final List<EndpointAddress> addresses;
  final String deviceIdHex;
  final int seq;

  const ResolvedInfraEndpoint({
    required this.addresses,
    required this.deviceIdHex,
    required this.seq,
  });
}

