// 2D-DHT Identity Resolution: Replicator-side store for AuthManifest +
// LivenessRecord records belonging to OTHER users.
//
// This handler runs on every node and serves as the K-bucket-side replica:
// - Accepts IDENTITY_AUTH_PUBLISH / IDENTITY_LIVE_PUBLISH from the wire layer.
// - Replays older sequence numbers (Replay-Schutz) silently.
// - Persists records via FileEncryption (encrypted JSON file) when wired up.
// - Periodically prunes records past their TTL.
// - Caps total stored records (LRU-evict farthest XOR-distance).
//
// Wire-Layer Sig-Verification happens BEFORE handleAuthPublish/handleLivePublish
// (in cleona_node.dart) because we need the user's pubkey from the contact
// registry — not from the manifest itself. The handler trusts what it receives
// and only enforces seq-monotonicity + TTL.

import 'dart:async';
import 'dart:typed_data';

import 'package:cleona/core/crypto/file_encryption.dart';
import 'package:cleona/core/identity_resolution/auth_manifest.dart';
import 'package:cleona/core/identity_resolution/liveness_record.dart';
import 'package:cleona/core/network/peer_info.dart' show bytesToHex, hexToBytes;
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;
import 'package:meta/meta.dart';

/// Replicator-side: empfängt IDENTITY_*_PUBLISH/RETRIEVE für andere Users.
/// Speichert Records in-memory + verschlüsselt auf Disk via FileEncryption.
class IdentityDhtHandler {
  final Uint8List ownNodeId;
  final FileEncryption? fileEncryption;
  final String? storagePath;

  // Storage-Caps
  static const int maxAuthManifests = 1000;
  static const int maxLivenessRecords = 5000;
  static const int maxRecordSizeBytes = 16 * 1024; // 16 KB sanity cap

  // userIdHex → AuthManifest
  final Map<String, AuthManifest> _storedAuthManifests = {};
  // (userIdHex, deviceNodeIdHex) joined with ":" → LivenessRecord
  final Map<String, LivenessRecord> _storedLiveness = {};

  Timer? _maintenanceTimer;
  Timer? _persistDebounce;

  IdentityDhtHandler({
    required this.ownNodeId,
    this.fileEncryption,
    this.storagePath,
  });

  Future<void> start() async {
    if (fileEncryption != null && storagePath != null) {
      await _loadFromDisk();
    }
    _maintenanceTimer = Timer.periodic(
        const Duration(seconds: 60), (_) => _runMaintenance());
  }

  void stop() {
    _maintenanceTimer?.cancel();
    _maintenanceTimer = null;
    _persistDebounce?.cancel();
    _persistDebounce = null;
  }

  // ── Auth-Manifest API ─────────────────────────────────────────

  /// Wird vom Wire-Layer aufgerufen wenn IDENTITY_AUTH_PUBLISH ankommt.
  /// Sig-Verification erfolgt in cleona_node.dart bevor wir hier landen,
  /// weil wir den Sender-Pubkey aus dem AuthManifest selbst holen
  /// (selbst-validierende Records).
  void handleAuthPublish(AuthManifest m) {
    final hex = bytesToHex(m.userId);
    final existing = _storedAuthManifests[hex];
    if (existing != null && m.sequenceNumber <= existing.sequenceNumber) {
      return; // Replay-Schutz
    }
    _storedAuthManifests[hex] = m;
    _enforceAuthCap();
    _persistAsync();
  }

  AuthManifest? getAuthManifest(Uint8List userId) {
    return _storedAuthManifests[bytesToHex(userId)];
  }

  // ── Liveness API ──────────────────────────────────────────────

  void handleLivePublish(LivenessRecord r) {
    final key = '${bytesToHex(r.userId)}:${bytesToHex(r.deviceNodeId)}';
    final existing = _storedLiveness[key];
    if (existing != null && r.sequenceNumber <= existing.sequenceNumber) {
      return;
    }
    _storedLiveness[key] = r;
    _enforceLivenessCap();
    _persistAsync();
  }

  LivenessRecord? getLiveness(Uint8List userId, Uint8List deviceNodeId) {
    final key = '${bytesToHex(userId)}:${bytesToHex(deviceNodeId)}';
    return _storedLiveness[key];
  }

  // ── Internal: cap enforcement ────────────────────────────────

  void _enforceAuthCap() {
    if (_storedAuthManifests.length <= maxAuthManifests) return;
    // LRU-Eviction nach XOR-Distanz: am weitesten entfernte Records first.
    final entries = _storedAuthManifests.entries.toList();
    entries.sort((a, b) => _xorDistance(hexToBytes(b.key))
        .compareTo(_xorDistance(hexToBytes(a.key))));
    final toEvict = entries.length - maxAuthManifests;
    for (var i = 0; i < toEvict; i++) {
      _storedAuthManifests.remove(entries[i].key);
    }
  }

  void _enforceLivenessCap() {
    if (_storedLiveness.length <= maxLivenessRecords) return;
    final entries = _storedLiveness.entries.toList();
    entries.sort((a, b) {
      // Key-Format ist "userIdHex:deviceNodeIdHex"; XOR-Dist auf userIdHex
      final aUserId = hexToBytes(a.key.split(':')[0]);
      final bUserId = hexToBytes(b.key.split(':')[0]);
      return _xorDistance(bUserId).compareTo(_xorDistance(aUserId));
    });
    final toEvict = entries.length - maxLivenessRecords;
    for (var i = 0; i < toEvict; i++) {
      _storedLiveness.remove(entries[i].key);
    }
  }

  /// XOR-Distance als BigInt für Sortier-Vergleich.
  BigInt _xorDistance(Uint8List recordKey) {
    var dist = BigInt.zero;
    for (var i = 0; i < ownNodeId.length && i < recordKey.length; i++) {
      dist = dist << 8;
      dist |= BigInt.from(ownNodeId[i] ^ recordKey[i]);
    }
    return dist;
  }

  // ── Maintenance: TTL-Prune ────────────────────────────────────

  @visibleForTesting
  void runMaintenance() => _runMaintenance();

  void _runMaintenance() {
    _storedAuthManifests.removeWhere((_, m) => m.isExpired());
    _storedLiveness.removeWhere((_, r) => r.isExpired());
    _persistAsync();
  }

  // ── Persistence ───────────────────────────────────────────────

  Future<void> _loadFromDisk() async {
    if (fileEncryption == null || storagePath == null) return;
    final data = fileEncryption!.readJsonFile(storagePath!);
    if (data == null) return;

    final auths = (data['authManifests'] as List?) ?? [];
    for (final entry in auths) {
      try {
        final bytes = hexToBytes(entry as String);
        final m = AuthManifest.fromProto(proto.AuthManifestProto.fromBuffer(bytes));
        if (!m.isExpired()) {
          _storedAuthManifests[bytesToHex(m.userId)] = m;
        }
      } catch (_) {/* skip corrupt */}
    }

    final lives = (data['liveness'] as List?) ?? [];
    for (final entry in lives) {
      try {
        final bytes = hexToBytes(entry as String);
        final r = LivenessRecord.fromProto(
            proto.LivenessRecordProto.fromBuffer(bytes));
        if (!r.isExpired()) {
          final key = '${bytesToHex(r.userId)}:${bytesToHex(r.deviceNodeId)}';
          _storedLiveness[key] = r;
        }
      } catch (_) {/* skip corrupt */}
    }
  }

  void _persistAsync() {
    if (fileEncryption == null || storagePath == null) return;
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(seconds: 5), _persistNow);
  }

  @visibleForTesting
  void persistNow() => _persistNow();

  void _persistNow() {
    if (fileEncryption == null || storagePath == null) return;
    fileEncryption!.writeJsonFile(storagePath!, {
      'authManifests': _storedAuthManifests.values
          .map((m) => bytesToHex(Uint8List.fromList(m.toProto().writeToBuffer())))
          .toList(),
      'liveness': _storedLiveness.values
          .map((r) => bytesToHex(Uint8List.fromList(r.toProto().writeToBuffer())))
          .toList(),
    });
  }

  // ── Test/Debug helpers ────────────────────────────────────────

  int get authManifestCount => _storedAuthManifests.length;
  int get livenessCount => _storedLiveness.length;

  /// Direct access to the in-memory auth-manifest store; used by tests
  /// that need to inject pre-built (e.g. expired) records to exercise prune.
  @visibleForTesting
  Map<String, AuthManifest> get debugAuthManifests => _storedAuthManifests;

  @visibleForTesting
  Map<String, LivenessRecord> get debugLiveness => _storedLiveness;
}
