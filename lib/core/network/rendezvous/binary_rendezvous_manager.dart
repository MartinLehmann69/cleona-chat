/// Binary Distribution Rendezvous Manager (§19.6.5).
///
/// Publishes and resolves binary-availability records (which nodes hold the
/// complete or partial application binary, per platform) under a
/// network-wide, platform-scoped tag derived from the network secret. No
/// user identity or contacts required — headless daemons participate.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/crypto/secp256k1_schnorr.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
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

const Duration kBinaryRefreshInterval = Duration(hours: 4);
const Duration kBinaryNetworkChangeDebounce = Duration(seconds: 15);

/// Platforms participating in binary-distribution rendezvous.
const List<String> kBinaryPlatforms = [
  'android',
  'linux',
  'windows',
  'macos',
  'ios',
];

// ---------------------------------------------------------------------------
// BinaryAvailabilityRecord (plaintext, inside AEAD)
// ---------------------------------------------------------------------------

class BinaryAvailabilityRecord {
  final Uint8List deviceId;
  final String platform;
  final String version;
  final List<EndpointAddress> addresses;
  final String binaryHash;
  final bool hasFullBinary;
  final List<int> fragmentIndices;
  final int seq;

  const BinaryAvailabilityRecord({
    required this.deviceId,
    required this.platform,
    required this.version,
    required this.addresses,
    required this.binaryHash,
    required this.hasFullBinary,
    required this.fragmentIndices,
    required this.seq,
  });

  Uint8List serialize() {
    final json = {
      'd': base64Encode(deviceId),
      'p': platform,
      'v': version,
      'a': addresses.map((a) => a.toJson()).toList(),
      'h': binaryHash,
      'f': hasFullBinary,
      'x': fragmentIndices,
      's': seq,
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(json)));
  }

  static BinaryAvailabilityRecord? deserialize(Uint8List data) {
    try {
      final json = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
      return BinaryAvailabilityRecord(
        deviceId: base64Decode(json['d'] as String),
        platform: json['p'] as String,
        version: json['v'] as String,
        addresses: (json['a'] as List)
            .map((e) => EndpointAddress.fromJson(e as Map<String, dynamic>))
            .toList(),
        binaryHash: json['h'] as String,
        hasFullBinary: json['f'] as bool,
        fragmentIndices:
            (json['x'] as List).map((e) => e as int).toList(),
        seq: json['s'] as int,
      );
    } catch (_) {
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// BinaryRendezvousManager (§19.6.5)
// ---------------------------------------------------------------------------

class BinaryRendezvousManager {
  final List<RendezvousProvider> _providers;
  final CLogger _log;

  Uint8List? _networkSecret;
  Uint8List? _deviceId;
  List<RendezvousAddress> Function()? _addressProvider;

  int _seq = 0;
  Timer? _refreshTimer;
  Timer? _debounceTimer;
  bool _disposed = false;

  BinaryRendezvousManager({
    List<RendezvousProvider>? providers,
    String? profileDir,
  })  : _providers = providers ?? [NostrProvider(profileDir: profileDir)],
        _log = CLogger.get('binary-rv', profileDir: profileDir);

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
  // Publish (§19.6.5)
  // -------------------------------------------------------------------------

  Future<void> publish(BinaryAvailabilityRecord record) async {
    final secret = _networkSecret;
    final devId = _deviceId;
    final addrFn = _addressProvider;
    if (secret == null || devId == null || addrFn == null) return;

    final addresses = addrFn();
    final publicAddresses =
        addresses.where((a) => !PeerAddress.isPrivateIp(a.ip)).toList();
    if (publicAddresses.isEmpty) {
      _log.debug('Binary-RV publish: no public addresses, skipping');
      return;
    }

    _seq++;
    final currentEpoch = currentEpochString();
    final nextEpoch = nextEpochString();

    final endpointAddresses =
        publicAddresses.map((a) => EndpointAddress(a.ip, a.port)).toList();

    final scopedRecord = BinaryAvailabilityRecord(
      deviceId: devId,
      platform: record.platform,
      version: record.version,
      addresses: endpointAddresses,
      binaryHash: record.binaryHash,
      hasFullBinary: record.hasFullBinary,
      fragmentIndices: record.fragmentIndices,
      seq: _seq,
    );

    final nostrSk = deriveBinaryNostrSecretKey(secret, devId);
    final nostrKp = secp256k1KeypairFromSecret(nostrSk);

    var publishCount = 0;
    for (final epoch in [currentEpoch, nextEpoch]) {
      final tag = computeBinaryTag(secret, epoch, record.platform);
      final key = deriveBinaryKey(secret, epoch);
      final encrypted = encryptBinaryRecord(scopedRecord, key, tag);

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
          _log.debug('Binary-RV publish failed: $e');
        }
      }
    }

    _log.info('Binary-RV: published to $publishCount provider-epoch pairs '
        '(platform=${record.platform}, seq=$_seq, '
        '${publicAddresses.length} public addresses)');
  }

  Future<void> publishAll(List<BinaryAvailabilityRecord> records) async {
    for (final record in records) {
      await publish(record);
    }
  }

  void onNetworkChanged(
      List<BinaryAvailabilityRecord> Function() recordsProvider) {
    if (_disposed) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(kBinaryNetworkChangeDebounce, () {
      publishAll(recordsProvider());
    });
  }

  void startPeriodicRefresh(
      List<BinaryAvailabilityRecord> Function() recordsProvider) {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(kBinaryRefreshInterval, (_) {
      publishAll(recordsProvider());
    });
  }

  /// §19.6.5 opt-out: stop the periodic re-publish without disposing the
  /// whole manager (providers/keys stay initialized so a later opt-in can
  /// resume immediately via [startPeriodicRefresh]).
  void stopPeriodicRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  // -------------------------------------------------------------------------
  // Resolve (§19.6.5)
  // -------------------------------------------------------------------------

  Future<List<ResolvedBinaryEndpoint>> resolve(String platform) async {
    final secret = _networkSecret;
    if (secret == null) return [];

    final currentEpoch = currentEpochString();
    final prevEpoch = previousEpochString();
    final results = <ResolvedBinaryEndpoint>[];
    final seenDevices = <String>{};

    for (final epoch in [currentEpoch, prevEpoch]) {
      final tag = computeBinaryTag(secret, epoch, platform);
      final key = deriveBinaryKey(secret, epoch);

      final allSigned = <SignedEndpointRecord>[];
      for (final p in _providers.where((p) => p.isAvailable)) {
        try {
          if (p is NostrProvider) {
            allSigned.addAll(await p.resolveMulti(tag));
          } else {
            final single = await p.resolve(tag);
            if (single != null) allSigned.add(single);
          }
        } catch (_) {}
      }

      for (final signed in allSigned) {
        final rec = decryptBinaryRecord(signed, key, tag);
        if (rec == null || rec.addresses.isEmpty) continue;
        final devHex = rec.deviceId
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
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
    }

    if (results.isNotEmpty) {
      _log.info('Binary-RV: resolved ${results.length} node(s) '
          'for platform=$platform');
    }
    return results;
  }

  /// Convenience: queries all known platforms and groups by platform.
  Future<Map<String, List<ResolvedBinaryEndpoint>>> resolveAll() async {
    final result = <String, List<ResolvedBinaryEndpoint>>{};
    for (final platform in kBinaryPlatforms) {
      result[platform] = await resolve(platform);
    }
    return result;
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
// Encrypt / Decrypt helpers — same AEAD envelope as EndpointRecord
// (AES-256-GCM, AAD = lookupTag), carrying BinaryAvailabilityRecord bytes.
// ---------------------------------------------------------------------------

SignedEndpointRecord encryptBinaryRecord(
  BinaryAvailabilityRecord record,
  Uint8List rendezvousSecret,
  Uint8List lookupTag,
) {
  final sodium = SodiumFFI();
  final plaintext = record.serialize();
  final nonce = sodium.generateNonce();
  final ciphertext = sodium.aesGcmEncrypt(
    plaintext,
    rendezvousSecret,
    nonce,
    ad: lookupTag,
  );
  return SignedEndpointRecord(
    nonce: nonce,
    ciphertext: ciphertext,
    seq: record.seq,
  );
}

BinaryAvailabilityRecord? decryptBinaryRecord(
  SignedEndpointRecord record,
  Uint8List rendezvousSecret,
  Uint8List lookupTag,
) {
  try {
    final plaintext = SodiumFFI().aesGcmDecrypt(
      record.ciphertext,
      rendezvousSecret,
      record.nonce,
      ad: lookupTag,
    );
    return BinaryAvailabilityRecord.deserialize(plaintext);
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Result type
// ---------------------------------------------------------------------------

class ResolvedBinaryEndpoint {
  final List<EndpointAddress> addresses;
  final String deviceIdHex;
  final String platform;
  final String version;
  final String binaryHash;
  final bool hasFullBinary;
  final List<int> fragmentIndices;
  final int seq;

  const ResolvedBinaryEndpoint({
    required this.addresses,
    required this.deviceIdHex,
    required this.platform,
    required this.version,
    required this.binaryHash,
    required this.hasFullBinary,
    required this.fragmentIndices,
    required this.seq,
  });
}
