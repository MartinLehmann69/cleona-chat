import 'dart:convert';
import 'dart:typed_data';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/network/clogger.dart';

/// Signed update manifest for decentralized update checking.
///
/// The manifest is signed with the maintainer Ed25519 key (same as donation verification).
/// Published to DHT under key SHA-256("cleona-update-manifest").
/// Clients verify the signature before presenting updates to the user.
class UpdateManifest {
  /// Current version string (semver).
  final String version;

  /// Download URL for the release.
  final String downloadUrl;

  /// SHA-256 hash of the release archive.
  final String archiveHash;

  /// Short changelog summary.
  final String changelog;

  /// Unix timestamp when this manifest was created.
  final int timestamp;

  /// Ed25519 signature over the manifest payload.
  final Uint8List signature;

  /// NEW (V3.1.72): if set, clients with `appVersion < minRequiredVersion` are hard-blocked.
  /// Null on legacy manifests.
  final String? minRequiredVersion;

  /// NEW (V3.1.72): i18n key for the hard-block reason text.
  /// Null on legacy manifests.
  final String? minRequiredReason;

  /// NEW (§19.6): per-platform DHT lookup tag for erasure-coded binary fragments.
  /// Keys: linux, windows, android, macos, ios. Null on legacy manifests.
  final Map<String, String>? dhtBinaryTag;

  /// NEW (§19.6): per-platform map from source-version to DHT tag for delta patches.
  /// Null on legacy manifests.
  final Map<String, Map<String, String>>? deltaBinaryTag;

  /// NEW (§19.6): monotonically increasing sequence number for downgrade protection.
  /// Null on legacy manifests.
  final int? minMonotoneSeq;

  /// NEW (§19.6.2): per-platform SHA-256 hash (hex) of the release binary.
  /// This is the trust anchor an in-network downloader verifies the
  /// assembled/reconstructed binary against — see
  /// [BinaryUpdateManager.verify]. Null on legacy manifests or manifests
  /// without in-network distribution.
  final Map<String, String>? binaryHashes;

  /// NEW (§19.6.2): per-platform Ed25519 signature (base64) by the
  /// maintainer key over the raw 32-byte SHA-256 hash of that platform's
  /// binary (same scheme as `PhysicalTransferHelper.importAndVerifyBinary`
  /// / `InviteLink`). Independent of [signature] (which covers the manifest
  /// payload as a whole) so the binary itself carries its own portable proof
  /// of authenticity. Null on legacy manifests.
  final Map<String, String>? binarySignatures;

  /// NEW (§19.6.2): per-platform exact byte size of the unpadded release
  /// binary, required to truncate the Reed-Solomon reconstruction back to
  /// the original binary (erasure-coded fragments are padded to a multiple
  /// of K). Null on legacy manifests.
  final Map<String, int>? binarySizes;

  UpdateManifest({
    required this.version,
    required this.downloadUrl,
    required this.archiveHash,
    required this.changelog,
    required this.timestamp,
    required this.signature,
    this.minRequiredVersion,
    this.minRequiredReason,
    this.dhtBinaryTag,
    this.deltaBinaryTag,
    this.minMonotoneSeq,
    this.binaryHashes,
    this.binarySignatures,
    this.binarySizes,
  });

  /// Payload to sign. Legacy format (no new fields) preserved when all new
  /// fields are null — keeps old manifests verifiable. When new fields are
  /// set, they are appended to the payload.
  String get signedPayload {
    final base = '$version\n$downloadUrl\n$archiveHash\n$changelog\n$timestamp';
    if (minRequiredVersion == null && minRequiredReason == null &&
        dhtBinaryTag == null && deltaBinaryTag == null && minMonotoneSeq == null &&
        binaryHashes == null && binarySignatures == null && binarySizes == null) {
      return base;
    }
    var payload = '$base\n${minRequiredVersion ?? ''}\n${minRequiredReason ?? ''}';
    if (dhtBinaryTag != null || deltaBinaryTag != null || minMonotoneSeq != null ||
        binaryHashes != null || binarySignatures != null || binarySizes != null) {
      payload += '\n${dhtBinaryTag != null ? jsonEncode(dhtBinaryTag) : ''}'
          '\n${deltaBinaryTag != null ? jsonEncode(deltaBinaryTag) : ''}'
          '\n${minMonotoneSeq ?? ''}'
          '\n${binaryHashes != null ? jsonEncode(binaryHashes) : ''}'
          '\n${binarySignatures != null ? jsonEncode(binarySignatures) : ''}'
          '\n${binarySizes != null ? jsonEncode(binarySizes) : ''}';
    }
    return payload;
  }

  /// Verify the manifest signature against the maintainer public key.
  bool verify(Uint8List maintainerPublicKey) {
    try {
      final message = Uint8List.fromList(utf8.encode(signedPayload));
      return SodiumFFI().verifyEd25519(message, signature, maintainerPublicKey);
    } catch (e) {
      return false;
    }
  }

  /// Serialize to JSON for DHT storage.
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'v': version,
      'url': downloadUrl,
      'hash': archiveHash,
      'log': changelog,
      'ts': timestamp,
      'sig': base64Encode(signature),
    };
    if (minRequiredVersion != null) json['minReq'] = minRequiredVersion;
    if (minRequiredReason != null) json['minReqReason'] = minRequiredReason;
    if (dhtBinaryTag != null) json['dhtBin'] = dhtBinaryTag;
    if (deltaBinaryTag != null) json['deltaBin'] = deltaBinaryTag;
    if (minMonotoneSeq != null) json['monotoneSeq'] = minMonotoneSeq;
    if (binaryHashes != null) json['binHash'] = binaryHashes;
    if (binarySignatures != null) json['binSig'] = binarySignatures;
    if (binarySizes != null) json['binSize'] = binarySizes;
    return json;
  }

  /// Deserialize from DHT JSON.
  static UpdateManifest? fromJson(Map<String, dynamic> json) {
    try {
      return UpdateManifest(
        version: json['v'] as String,
        downloadUrl: json['url'] as String,
        archiveHash: json['hash'] as String,
        changelog: json['log'] as String,
        timestamp: json['ts'] as int,
        signature: base64Decode(json['sig'] as String),
        minRequiredVersion: json['minReq'] as String?,
        minRequiredReason: json['minReqReason'] as String?,
        dhtBinaryTag: (json['dhtBin'] as Map?)?.map(
          (k, v) => MapEntry(k as String, v as String),
        ),
        deltaBinaryTag: (json['deltaBin'] as Map?)?.map(
          (k, v) => MapEntry(
            k as String,
            (v as Map).map((k2, v2) => MapEntry(k2 as String, v2 as String)),
          ),
        ),
        minMonotoneSeq: json['monotoneSeq'] as int?,
        binaryHashes: (json['binHash'] as Map?)?.map(
          (k, v) => MapEntry(k as String, v as String),
        ),
        binarySignatures: (json['binSig'] as Map?)?.map(
          (k, v) => MapEntry(k as String, v as String),
        ),
        binarySizes: (json['binSize'] as Map?)?.map(
          (k, v) => MapEntry(k as String, v as int),
        ),
      );
    } catch (e) {
      return null;
    }
  }

  /// DHT key for the update manifest.
  static Uint8List dhtKey() {
    return SodiumFFI().sha256(
      Uint8List.fromList(utf8.encode('cleona-update-manifest')),
    );
  }

  @override
  String toString() => 'UpdateManifest(v$version, $downloadUrl, ts=$timestamp, minReq=$minRequiredVersion, '
      'dhtBin=$dhtBinaryTag, deltaBin=$deltaBinaryTag, monotoneSeq=$minMonotoneSeq, '
      'binHash=$binaryHashes, binSize=$binarySizes)';
}

/// Checks for updates via DHT.
class UpdateChecker {
  final CLogger _log;

  /// Maintainer public key (hex) — same as donation verification.
  static const String maintainerPublicKeyHex =
      '8a8589febfca4e0cecc21b036621861c4595192d56cfd1f5ec6573eece932daa';

  UpdateChecker({CLogger? log}) : _log = log ?? CLogger('UpdateChecker');

  /// Parse and verify an update manifest from DHT data.
  ///
  /// Returns the manifest if signature is valid, null otherwise.
  UpdateManifest? verifyManifest(String jsonData) {
    try {
      final json = jsonDecode(jsonData) as Map<String, dynamic>;
      final manifest = UpdateManifest.fromJson(json);
      if (manifest == null) return null;

      final pubKey = _hexToBytes(maintainerPublicKeyHex);
      if (!manifest.verify(pubKey)) {
        _log.warn('Update manifest signature verification FAILED');
        return null;
      }

      _log.info('Update manifest verified: v${manifest.version}');
      return manifest;
    } catch (e) {
      _log.warn('Failed to parse update manifest: $e');
      return null;
    }
  }

  /// Check if a manifest version is newer than the current version.
  bool isNewer(String manifestVersion, String currentVersion) {
    final mv = _parseVersion(manifestVersion);
    final cv = _parseVersion(currentVersion);
    if (mv == null || cv == null) return false;

    for (var i = 0; i < 3; i++) {
      if (mv[i] > cv[i]) return true;
      if (mv[i] < cv[i]) return false;
    }
    return false; // equal
  }

  /// Hard-block check (Sec H-5 V3.1.72): true if the manifest specifies a
  /// minRequiredVersion AND the current app version is older.
  bool isHardBlocked(UpdateManifest manifest, String currentVersion) {
    final minReq = manifest.minRequiredVersion;
    if (minReq == null) return false;
    final mv = _parseVersion(minReq);
    final cv = _parseVersion(currentVersion);
    if (mv == null || cv == null) return false;
    for (var i = 0; i < 3; i++) {
      if (cv[i] < mv[i]) return true;
      if (cv[i] > mv[i]) return false;
    }
    return false;  // equal → not blocked
  }

  /// Downgrade protection (§19.6): true if the manifest's minMonotoneSeq is
  /// not newer than the highest sequence number this node has already seen.
  bool isDowngradeAttempt(UpdateManifest manifest, int highestSeenSeq) {
    return manifest.minMonotoneSeq != null && manifest.minMonotoneSeq! <= highestSeenSeq;
  }

  List<int>? _parseVersion(String version) {
    final parts = version.replaceAll('+', '.').split('.');
    if (parts.length < 3) return null;
    try {
      return [int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2])];
    } catch (_) {
      return null;
    }
  }

  Uint8List _hexToBytes(String hex) {
    final bytes = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }
}
