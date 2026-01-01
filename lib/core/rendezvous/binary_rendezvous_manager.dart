/// Binary Distribution Rendezvous Manager (§19.6.5).
///
/// Publishes and resolves binary-availability records (which nodes hold the
/// complete or partial application binary, per platform) under a
/// network-wide, platform-scoped tag derived from the network secret. No
/// user identity or contacts required — infrastructure daemons participate.
library;

import 'package:cleona/core/rendezvous/nostr_provider.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// `secp256k1_schnorr.dart` stood here until S361 for
// `secp256k1KeypairFromSecret`, whose result was never used. Why
// this manager sets NO derived signing key stands at
// `publish()`.
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/log/clogger.dart';
import 'package:cleona/core/util/ip_address_class.dart';
import 'package:cleona/core/rendezvous/rendezvous_provider.dart';
import 'package:cleona/core/rendezvous/rendezvous_types.dart'
    show RendezvousAddress;
import 'package:cleona/core/rendezvous/rendezvous_secret.dart';

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
  final String? _profileDir;

  Uint8List? _networkSecret;
  Uint8List? _previousNetworkSecret;
  Uint8List? _deviceId;
  List<RendezvousAddress> Function()? _addressProvider;

  int _seq = 0;
  Timer? _refreshTimer;
  Timer? _debounceTimer;
  bool _disposed = false;

  BinaryRendezvousManager({
    List<RendezvousProvider>? providers,
    String? profileDir,
  })  : _profileDir = profileDir,
        _providers = _providersOrDefault(providers, profileDir),
        _log = CLogger.get('binary-rv', profileDir: profileDir);

  List<RendezvousProvider> get providers =>
      List.unmodifiable(_providers);

  /// [previousNetworkSecret] — the outgoing secret during a rotation
  /// (Architecture 13.2). Pass `NetworkSecret.previousSecret`; `null` outside a
  /// transition window, which leaves behaviour unchanged.
  void init({
    required Uint8List networkSecret,
    required Uint8List deviceId,
    required List<RendezvousAddress> Function() addressProvider,
    Uint8List? previousNetworkSecret,
  }) {
    _networkSecret = networkSecret;
    _previousNetworkSecret = previousNetworkSecret;
    _deviceId = deviceId;
    _addressProvider = addressProvider;
    _loadSeq();
  }

  /// Secrets to publish under and resolve against (R-2).
  ///
  /// Binary discovery is the load-bearing case for this: it is how a node
  /// finds the update that carries it across a secret rotation. If a rotated
  /// publisher and an un-rotated resolver use different tags, the un-rotated
  /// build cannot discover the very binary that would keep it in the network
  /// past the transition window. See [InfraRendezvousManager] for the general
  /// rationale (the rendezvous epoch is a time window, not a secret version).
  List<Uint8List> get _tagSecrets => [
        ?_networkSecret,
        ?_previousNetworkSecret,
      ];

  void _loadSeq() {
    final dir = _profileDir;
    if (dir == null) return;
    try {
      final file = File('$dir/rendezvous_seq');
      if (file.existsSync()) {
        _seq = int.tryParse(file.readAsStringSync().trim()) ?? 0;
      }
    } catch (_) {
      _seq = 0;
    }
  }

  void _saveSeq() {
    final dir = _profileDir;
    if (dir == null) return;
    try {
      File('$dir/rendezvous_seq').writeAsStringSync('$_seq');
    } catch (_) {}
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
        addresses.where((a) => !IpAddressClass.isPrivate(a.ip)).toList();
    if (publicAddresses.isEmpty) {
      _log.debug('Binary-RV publish: no public addresses, skipping');
      return;
    }

    _seq++;
    _saveSeq();
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

    var publishCount = 0;
    // R-2: publish under every active secret.
    //
    // HERE IT STAYS WITH THE THROWAWAY KEY — and that is a decision,
    // not an omission. Re-measured on 01.09.2026 (S361).
    //
    // Until S361 this said "the Nostr signing key is secret-derived, so it is
    // re-derived per secret", and below that `deriveBinaryNostrSecretKey`
    // was called and the result THROWN AWAY — `provider.publish` drew
    // a new random pair every time (`nostr_provider.dart:192-195`).
    // The comment thus did not describe the code. It has been removed instead of
    // making it true through the call:
    //
    //   Price of the switch. `deriveBinaryNostrSecretKey` takes as ikm the
    //   NETWORK SECRET and as info only `hex(deviceId)` — the epoch is
    //   NOT in it (`rendezvous_secret.dart:168-178`). The signing key
    //   thus survives every tag rotation. On the relay side there would arise a
    //   device pseudonym stable over the lifetime of the network secret
    //   under a NETWORK-WIDE shared tag: the relay operator could
    //   join the 6 h tags into a chain, count the nodes and
    //   track the IP sequence of a device over months. For first contact
    //   the same calculation comes out differently, because there the one-time nonce of the
    //   invitation is the ikm (see there).
    //
    //   Price of staying. Every republication lies next to the
    //   previous one instead of replacing it (NIP-33, kind 30078 + `d` tag).
    //   Timed, that is 4 h (`kBinaryRefreshInterval`) x 2 epochs x
    //   platforms, plus the network change debouncer.
    //
    //   What tips the balance: v3_0 §19.6.5/§4.11.9 prescribes the
    //   derived key, but on the V4 line v4_1 leads
    //   (CLAUDE.md), and v4_1 §26.6.4 withdraws the external carrier for the
    //   binary rendezvous ENTIRELY: "The binary-rendezvous design
    //   therefore has no external service at all" — the resolution is to
    //   run via the entry cascade (§11), and §26.6.8 lists
    //   `BinaryRendezvousManager` exactly as its resolver. Giving a place
    //   that the leading document abolishes a permanent,
    //   relay-visible identifier now would be the wrong direction — all
    //   the more next to RL-13/§23.7 (enumerability).
    //
    //   OPEN FOR THE OWNER (stage C): either clear away this Nostr path according to
    //   §26.6.4, or — if it stays — derive the signing key WITH
    //   the epoch in the info field. The latter would have both: the
    //   key would be stable within one tag (replaced in place) and
    //   would rotate with it (not linkable). But it deviates from the derivation
    //   WRITTEN in v3_0 §19.6.5 (`info = hex(own_device_id)`) and
    //   is thus a document change, not an implementation. The same question
    //   stands in `infra_rendezvous_manager.dart`.
    for (final tagSecret in _tagSecrets) {
      for (final epoch in [currentEpoch, nextEpoch]) {
        final tag = computeBinaryTag(tagSecret, epoch, record.platform);
        final key = deriveBinaryKey(tagSecret, epoch);
        final encrypted = encryptBinaryRecord(scopedRecord, key, tag);

        for (final provider in _providers) {
          if (!provider.isAvailable) continue;
          try {
              await provider.publish(tag, encrypted);
            publishCount++;
          } catch (e) {
            _log.debug('Binary-RV publish failed: $e');
          }
        }
      }
    }

    _log.info('Binary-RV: published to $publishCount provider-epoch pairs '
        '(platform=${record.platform}, seq=$_seq, '
        '${publicAddresses.length} public addresses, '
        '${_tagSecrets.length} secret(s))');
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
    final seenDevices = <String, int>{};

    // R-2: resolve under every active secret — an un-rotated publisher is only
    // findable under the old tag, and it is exactly the peer that needs to be
    // found so it can fetch the update.
    for (final tagSecret in _tagSecrets) {
      for (final epoch in [currentEpoch, prevEpoch]) {
        final tag = computeBinaryTag(tagSecret, epoch, platform);
        final key = deriveBinaryKey(tagSecret, epoch);

        final allSigned = <SignedEndpointRecord>[];
        for (final p in _providers.where((p) => p.isAvailable)) {
          try {
            final single = await p.resolve(tag);
            if (single != null) allSigned.add(single);
          } catch (_) {}
        }

        for (final signed in allSigned) {
          final rec = decryptBinaryRecord(signed, key, tag);
          if (rec == null || rec.addresses.isEmpty) continue;
          final devHex = rec.deviceId
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join();
          final endpoint = ResolvedBinaryEndpoint(
            addresses: rec.addresses,
            deviceIdHex: devHex,
            platform: rec.platform,
            version: rec.version,
            binaryHash: rec.binaryHash,
            hasFullBinary: rec.hasFullBinary,
            fragmentIndices: rec.fragmentIndices,
            seq: rec.seq,
          );
          if (seenDevices.containsKey(devHex)) {
            final existingIdx = seenDevices[devHex]!;
            if (rec.seq > results[existingIdx].seq) {
              results[existingIdx] = endpoint;
            }
            continue;
          }
          seenDevices[devHex] = results.length;
          results.add(endpoint);
        }
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

/// Throws if the provider list is empty.
///
/// V4.1 has shut down the Nostr provider (§26.6.4); a replacement provider
/// comes from the entry cascade (§11) and is work of WP-0/WP-2. Until
/// then the list is empty — and an empty list is NOT a silent
/// state here: all uses of `_providers` are loops, an empty
/// list would thus run through without an iteration and make the rendezvous path
/// silently ineffective. Exactly that is supposed to stand out instead of
/// disappearing in the field.

/// The default when no provider was passed.
///
/// RESTORED 2026-08-22. The clearing had left a `StateError` here,
/// so that the absence of the Nostr provider "stands out instead of disappearing
/// in the field". It did stand out — on the phone, at the first
/// test build of the V4.1 line: `_initInProcess FAILED`, and with it the
/// whole service initialisation. The throw thus did exactly what it was
/// there for.
///
/// Since the decision "all three cold-start sources, the external one stays"
/// (§11.3) the provider exists again, and thus the default belongs
/// back.
List<RendezvousProvider> _providersOrDefault(
        List<RendezvousProvider>? p, String? profileDir) =>
    (p == null || p.isEmpty)
        ? [NostrProvider(profileDir: profileDir)]
        : p;
