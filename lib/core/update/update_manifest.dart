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

  UpdateManifest({
    required this.version,
    required this.downloadUrl,
    required this.archiveHash,
    required this.changelog,
    required this.timestamp,
    required this.signature,
  });

  /// The payload that gets signed: "version\ndownloadUrl\narchiveHash\nchangelog\ntimestamp".
  String get signedPayload =>
      '$version\n$downloadUrl\n$archiveHash\n$changelog\n$timestamp';

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
  Map<String, dynamic> toJson() => {
        'v': version,
        'url': downloadUrl,
        'hash': archiveHash,
        'log': changelog,
        'ts': timestamp,
        'sig': base64Encode(signature),
      };

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
  String toString() => 'UpdateManifest(v$version, $downloadUrl, ts=$timestamp)';
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
