import 'dart:convert';
import 'dart:typed_data';
import 'package:cleona/core/crypto/hd_wallet.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/erasure/reed_solomon.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/peer_info.dart' show bytesToHex;

/// Manages the DHT-based identity registry for Multi-Identity recovery.
///
/// When a user has multiple HD-wallet derived identities, the registry
/// stores which indices are active (with display names) in the DHT.
/// After recovery from seed phrase, this registry is fetched to know
/// which identities to re-derive.
///
/// Storage:
/// - DHT Key: SHA-256(master_seed + "cleona-registry-id")
/// - Encryption: XSalsa20-Poly1305 with SHA-256(master_seed + "cleona-registry-key")
/// - Erasure-coded: N=10, K=7 fragments distributed to closest DHT peers
///
/// Payload format (JSON, encrypted):
/// {
///   "version": 1,
///   "identities": [
///     {"index": 0, "name": "Alice", "active": true},
///     {"index": 1, "name": "AllyCat", "active": true}
///   ],
///   "next_index": 2,
///   "updated_at": 1711234567890
/// }
class IdentityDhtRegistry {
  final Uint8List masterSeed;
  final CLogger _log;
  final SodiumFFI _sodium = SodiumFFI();

  late final Uint8List registryDhtKey;
  late final Uint8List encryptionKey;

  IdentityDhtRegistry({required this.masterSeed, String? profileDir})
      : _log = CLogger.get('identity-registry', profileDir: profileDir) {
    registryDhtKey = HdWallet.registryId(masterSeed);
    encryptionKey = HdWallet.registryKey(masterSeed);
  }

  /// Build the registry payload from current identities.
  /// [identities] is a list of {index, name, active} maps.
  Uint8List buildPayload(List<Map<String, dynamic>> identities, int nextIndex) {
    final json = {
      'version': 1,
      'identities': identities,
      'next_index': nextIndex,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    };
    final plaintext = Uint8List.fromList(utf8.encode(jsonEncode(json)));

    // Encrypt with XSalsa20-Poly1305
    final nonce = _sodium.randomBytes(24);
    final ciphertext = _sodium.secretBoxEncrypt(plaintext, encryptionKey, nonce);

    // Format: [24B nonce][ciphertext]
    final result = Uint8List(24 + ciphertext.length);
    result.setRange(0, 24, nonce);
    result.setRange(24, result.length, ciphertext);

    _log.info('Registry payload built: ${identities.length} identities, ${result.length} bytes');
    return result;
  }

  /// Decode and decrypt a registry payload.
  /// Returns null if decryption fails or payload is invalid.
  Map<String, dynamic>? decodePayload(Uint8List data) {
    if (data.length <= 24) return null;

    try {
      final nonce = Uint8List.fromList(data.sublist(0, 24));
      final ciphertext = Uint8List.fromList(data.sublist(24));
      final plaintext = _sodium.secretBoxDecrypt(ciphertext, encryptionKey, nonce);
      return jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
    } catch (e) {
      _log.error('Registry payload decode failed: $e');
      return null;
    }
  }

  /// Erasure-code the registry payload into fragments.
  /// Returns a list of (fragmentIndex, fragmentData) pairs.
  List<({int index, Uint8List data})> encodeFragments(Uint8List payload) {
    final rs = ReedSolomon();
    final fragments = rs.encode(payload);

    return List.generate(fragments.length, (i) => (
      index: i,
      data: fragments[i],
    ));
  }

  /// Reassemble the registry payload from fragments.
  /// Needs at least K (default 7) fragments.
  /// Returns null if reassembly fails.
  Uint8List? reassembleFragments(
    Map<int, Uint8List> fragmentMap,
    int originalSize,
  ) {
    if (fragmentMap.length < ReedSolomon.defaultK) {
      _log.warn('Not enough fragments: ${fragmentMap.length}/${ReedSolomon.defaultK}');
      return null;
    }

    try {
      final rs = ReedSolomon();
      return rs.decode(fragmentMap, originalSize);
    } catch (e) {
      _log.error('Registry fragment reassembly failed: $e');
      return null;
    }
  }

  /// Extract identity list from decoded registry payload.
  /// Returns list of {index: int, name: String, active: bool} maps.
  static List<Map<String, dynamic>> extractIdentities(Map<String, dynamic> payload) {
    final version = payload['version'] as int? ?? 0;
    if (version != 1) return [];

    final identities = payload['identities'] as List<dynamic>? ?? [];
    return identities
        .map((e) => e as Map<String, dynamic>)
        .where((e) => e['active'] == true)
        .toList();
  }

  /// Get the next HD index from a decoded registry payload.
  static int extractNextIndex(Map<String, dynamic> payload) {
    return payload['next_index'] as int? ?? 0;
  }

  /// Build identity entries for the current state.
  /// Reads from IdentityManager's identity list.
  static List<Map<String, dynamic>> buildIdentityEntries(
    List<({int? hdIndex, String name})> identities,
  ) {
    return identities
        .where((id) => id.hdIndex != null)
        .map((id) => {
              'index': id.hdIndex,
              'name': id.name,
              'active': true,
            })
        .toList();
  }

  /// Registry DHT key as hex string (for logging/debugging).
  String get registryDhtKeyHex => bytesToHex(registryDhtKey);

  // ── Recovery Orchestration (Architecture Section 6.4.3) ────────────

  /// Attempt to recover the identity registry from DHT fragments.
  ///
  /// [retrieveFunction] sends FRAGMENT_RETRIEVE for a given mailboxId to all
  /// known peers and returns collected fragments (called by CleonaService).
  ///
  /// Returns the decoded registry payload, or null if recovery fails.
  Map<String, dynamic>? recoverFromFragments(Map<int, Uint8List> fragments, int originalSize) {
    // Step 1: Reassemble from erasure-coded fragments
    final reassembled = reassembleFragments(fragments, originalSize);
    if (reassembled == null) {
      _log.warn('Registry recovery: reassembly failed (${fragments.length} fragments)');
      return null;
    }

    // Step 2: Decrypt
    final payload = decodePayload(reassembled);
    if (payload == null) {
      _log.warn('Registry recovery: decryption failed');
      return null;
    }

    _log.info('Registry recovery successful: ${extractIdentities(payload).length} identities');
    return payload;
  }

  /// Store the registry in the DHT as erasure-coded fragments.
  ///
  /// [storeFunction] takes (Uint8List mailboxId, int fragmentIndex, Uint8List fragmentData)
  /// and stores the fragment via FRAGMENT_STORE to the closest DHT peers.
  void storeInDht(
    List<Map<String, dynamic>> identities,
    int nextIndex,
    void Function(Uint8List mailboxId, int fragmentIndex, Uint8List fragmentData) storeFunction,
  ) {
    final payload = buildPayload(identities, nextIndex);
    final fragments = encodeFragments(payload);

    for (final frag in fragments) {
      storeFunction(registryDhtKey, frag.index, frag.data);
    }

    _log.info('Registry stored in DHT: ${fragments.length} fragments, ${payload.length} bytes');
  }
}
