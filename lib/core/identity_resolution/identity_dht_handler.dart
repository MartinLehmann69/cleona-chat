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
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/crypto/file_encryption.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/identity_resolution/auth_manifest.dart';
import 'package:cleona/core/identity_resolution/rotation_co_auth.dart';
import 'package:cleona/core/identity_resolution/device_kem_record.dart';
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

  /// D1 (§4.3 Trust anchor): userId-Ableitung fuer die Store-Time-
  /// Verifikation eingehender AuthManifests. Null (alte Tests) → nur
  /// Sig-Selbstkonsistenz-Check, keine Anker-Bindung.
  final Uint8List Function(Uint8List ed25519Pk)? deriveUserId;

  // Storage-Caps
  static const int maxAuthManifests = 1000;
  static const int maxLivenessRecords = 5000;
  static const int maxKemRecords = 5000;
  static const int maxRecordSizeBytes = 16 * 1024; // 16 KB sanity cap

  // userIdHex → AuthManifest
  final Map<String, AuthManifest> _storedAuthManifests = {};
  // (userIdHex, deviceNodeIdHex) joined with ":" → LivenessRecord
  final Map<String, LivenessRecord> _storedLiveness = {};
  // (userIdHex, deviceIdHex) joined with ":" → DeviceKemRecord (Welle 5, §4.3)
  final Map<String, DeviceKemRecord> _storedKemRecords = {};

  /// §7.5: fired when a stored AuthManifest shrinks its device set without
  /// valid co-auth proof. Args: userId, oldDeviceCount, newDeviceCount.
  void Function(Uint8List userId, int oldCount, int newCount)?
      _onDeviceSetShrinkWithoutProof;

  set onDeviceSetShrinkWithoutProof(
      void Function(Uint8List userId, int oldCount, int newCount)? cb) {
    _onDeviceSetShrinkWithoutProof = cb;
  }

  Timer? _maintenanceTimer;
  Timer? _persistDebounce;

  final CLogger _log = CLogger.get('identity-dht');

  IdentityDhtHandler({
    required this.ownNodeId,
    this.fileEncryption,
    this.storagePath,
    this.deriveUserId,
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
  ///
  /// D1 (§4.3 Trust anchor) — Store-Time-Verifikation: forged Manifests
  /// werden hier verworfen, BEVOR sie per seq-Monotonie legitime
  /// Republishes blockieren koennen (ein forged Record mit seq=999 wuerde
  /// sonst den echten Publisher dauerhaft aussperren). Verified schlaegt
  /// legacy auch am Store; ein verankertes Manifest wird nur durch ein
  /// passendes (oder per Rotationskette brueckendes) ersetzt.
  void handleAuthPublish(AuthManifest m) {
    final hex = bytesToHex(m.userId);

    var incomingVerified = false;
    if (m.hasEmbeddedKeys) {
      if (deriveUserId != null) {
        final status = m.verifySelfCertified(deriveUserId: deriveUserId!);
        if (status != AnchorStatus.verified) return; // forged → silent drop
        incomingVerified = true;
      } else {
        // Kein deriveUserId injiziert (Test-Skeletons): mindestens die
        // Sig-Selbstkonsistenz der embedded Keys verlangen.
        if (!m.verify(m.userEd25519Pk, m.userMlDsaPk)) return;
        incomingVerified = true;
      }
    } else if (m.deviceDelegations.isNotEmpty || m.deviceSigKeys.isNotEmpty) {
      // A-2 (§7.1.1): a manifest without embedded User-PKs is unverifiable
      // by construction, so it must not be able to smuggle in device-bound
      // authority. `AuthManifest.sign()` populates userEd25519Pk/userMlDsaPk
      // unconditionally and is the only signing path (the sole other
      // constructor is `fromProto`) — a genuine manifest therefore never
      // combines "no embedded keys" with delegations or device sig keys.
      // Legacy stock without those fields stays accepted.
      _log.warn('A-2: AuthManifest for ${hex.substring(0, 16)}... dropped — '
          'device-bound fields without embedded User-PKs '
          '(delegations=${m.deviceDelegations.length}, '
          'sigKeys=${m.deviceSigKeys.length})');
      return;
    }

    final existing = _storedAuthManifests[hex];
    if (existing != null) {
      final existingVerified = existing.hasEmbeddedKeys;
      if (existingVerified && !incomingVerified) {
        return; // legacy ersetzt nie ein verankertes Manifest (§4.3 TOFU)
      }
      if (existingVerified && incomingVerified) {
        // Anker-Kontinuitaet: gleicher Pk oder brueckende Rotationskette.
        final sameAnchor =
            _pkEqual(existing.userEd25519Pk, m.userEd25519Pk) ||
                m.rotationChain.any(
                    (l) => _pkEqual(l.oldEd25519Pk, existing.userEd25519Pk));
        if (!sameAnchor) return;
      }
      if (!(incomingVerified && !existingVerified) &&
          m.sequenceNumber <= existing.sequenceNumber) {
        return; // Replay-Schutz (verified-beats-legacy ignoriert seq)
      }
    }
    if (incomingVerified) {
      _log.info('D1: verankertes AuthManifest fuer '
          '${hex.substring(0, 16)}... gespeichert (seq=${m.sequenceNumber})');
    }
    // §7.5: detect device-set shrink without co-auth proof.
    if (existing != null &&
        existing.deviceSigKeys.length >= 2 &&
        m.deviceSigKeys.isNotEmpty &&
        m.deviceSigKeys.length < existing.deviceSigKeys.length) {
      if (m.deviceSetChangeProof == null) {
        _log.warn('§7.5 DEVICE-SET SHRINK without proof for '
            '${hex.substring(0, 16)}...: '
            '${existing.deviceSigKeys.length}→${m.deviceSigKeys.length} '
            'devices (seq ${existing.sequenceNumber}→${m.sequenceNumber})');
        _onDeviceSetShrinkWithoutProof?.call(
            m.userId, existing.deviceSigKeys.length, m.deviceSigKeys.length);
      } else {
        final proof = m.deviceSetChangeProof!;
        final changeHash = computeDeviceSetChangeHash(
          userId: m.userId,
          newDeviceNodeIds: m.authorizedDeviceNodeIds,
          newSeq: m.sequenceNumber,
        );
        final result = verifyRotationCoAuth(
          tokens: proof.approvals,
          // Pre-change pubkeys: the incoming manifest nominates its own
          // `deviceSigKeys`, so counting tokens against those would let the
          // shrinking party also pick who vouches for the shrink.
          cachedDeviceSigKeys: existing.deviceSigKeys,
          rotationHash: changeHash,
          occasion: CoAuthOccasion.deviceSetChange,
          // Quorum over what REMAINS, not over `existing` — the removed
          // devices cannot consent to their own removal, and a one-device
          // remainder can never produce the two signatures the key-rotation
          // quorum demands. `proof.previousDeviceCount` stays purely
          // descriptive (it is the sender's claim, not a verified quantity).
          remainingDeviceCount: m.deviceSigKeys.length,
        );
        if (result == RotationCoAuthResult.quorumNotMet) {
          _log.warn('§7.5 DEVICE-SET SHRINK with INSUFFICIENT proof for '
              '${hex.substring(0, 16)}...: '
              '${existing.deviceSigKeys.length}→${m.deviceSigKeys.length}');
          _onDeviceSetShrinkWithoutProof?.call(
              m.userId, existing.deviceSigKeys.length, m.deviceSigKeys.length);
        }
      }
    }
    _storedAuthManifests[hex] = m;
    _enforceAuthCap();
    _persistAsync();
  }

  AuthManifest? getAuthManifest(Uint8List userId) {
    return _storedAuthManifests[bytesToHex(userId)];
  }

  /// §7.1 LD-4: extract delegated signing PKs from a cached AuthManifest.
  ///
  /// A-2 (§7.1.1): the result is consumed by `V3FrameCodec` as the fallback
  /// after a failed User-Sig — a key returned here makes a frame count as
  /// authentically sent by [userId]. Expiry alone is therefore not enough:
  ///
  /// 1. A manifest WITHOUT embedded User-PKs cannot prove a delegation at
  ///    all (there is nothing to verify the cert against), so it yields
  ///    nothing. `AuthManifest.sign()` always embeds the User-PKs, hence no
  ///    legitimately signed manifest ever lands in this branch.
  /// 2. Every cert must carry a valid HYBRID signature (Ed25519 AND ML-DSA)
  ///    by the User-Key: "Forging a delegation requires breaking both
  ///    signature schemes" (§7.1.1). Only reached on the rare post-User-Sig-
  ///    failure path, so the ML-DSA cost is not on the hot path.
  List<({Uint8List edPk, Uint8List mlDsaPk})> getDelegatedKeys(Uint8List userId) {
    final m = _storedAuthManifests[bytesToHex(userId)];
    if (m == null || m.deviceDelegations.isEmpty) return const [];
    if (!m.hasEmbeddedKeys) return const [];
    return m.deviceDelegations
        .where((d) =>
            !d.isExpired() && d.verify(m.userEd25519Pk, m.userMlDsaPk))
        .map((d) => (edPk: d.delegatedEd25519Pk, mlDsaPk: d.delegatedMlDsaPk))
        .toList();
  }

  // ── Liveness API ──────────────────────────────────────────────

  /// A-4 (§2.4.1a Empfaenger-Pipeline [11''], §4.3 D1): spiegelbildlich zu
  /// [handleKemPublish]. Liefert `true` NUR, wenn der Record gegen den
  /// verankerten User-Pk signaturverifiziert UND neu angenommen wurde.
  /// Der Wire-Layer benutzt den Rueckgabewert als Gate fuer das Seeding der
  /// Routing-Tabelle — ein unverifizierter Record darf dort keine Adressen
  /// platzieren (§2.3.5: „The Closed-Network HMAC alone never authenticates
  /// user-bound claims").
  ///
  /// Ohne Anker (kein AuthManifest mit embedded Keys fuer diese userId)
  /// traegt der Record nichts, womit er sich authentisieren koennte:
  /// [LivenessRecord] hat KEIN Pubkey-Feld — nur userId, deviceNodeId,
  /// addresses, seq und die Ed25519-Sig. „claimed userPk" ist also
  /// ausschliesslich ueber den Anker aufloesbar. Der Record wird in dem Fall
  /// weiterhin gespeichert (Transition/Cold-Start: ein Replikator muss auch
  /// fuer User liefern koennen, deren Manifest er noch nicht geholt hat),
  /// aber als UNVERIFIZIERT gemeldet.
  bool handleLivePublish(LivenessRecord r) {
    // D1: liegt fuer den User ein verankertes AuthManifest vor, muss die
    // Liveness-Sig gegen den Anker verifizieren — sonst kann ein forged
    // Record mit hoher seq den echten verdraengen.
    //
    // §7.1.4: „gegen den Anker" heisst seit der delegierten Signatur nicht
    // mehr zwingend „direkt". Ein Linked Device signiert mit seinem
    // delegierten Schluessel; `verifyAnchored` laeuft dann Anker →
    // Zertifikat → delegierter PK → Record. Ohne diesen Pfad wuerde JEDER
    // Empfaenger die Records eines gekoppelten Geraets nach einer
    // Emergency-Rotation verwerfen und das Geraet damit fuer alle Kontakte
    // unauffindbar machen.
    //
    // P6: das Zertifikat kommt aus genau diesem Manifest
    // (`delegationFor(deviceNodeId)`) statt aus dem Record. Kennt das Manifest
    // die Delegation nicht, ist der Record ein Drop — fail-closed.
    final anchorManifest = _anchorManifestFor(r.userId);
    if (anchorManifest != null && !r.verifyAnchored(anchorManifest)) {
      return false;
    }
    final anchor = anchorManifest?.userEd25519Pk;
    final key = '${bytesToHex(r.userId)}:${bytesToHex(r.deviceNodeId)}';
    final existing = _storedLiveness[key];
    if (existing != null && r.sequenceNumber <= existing.sequenceNumber) {
      return false; // Replay-Schutz
    }
    _storedLiveness[key] = r;
    _enforceLivenessCap();
    _persistAsync();
    return anchor != null;
  }

  /// A-4: hat dieser Node einen Trust-Anker (AuthManifest mit embedded Keys)
  /// fuer [userId]? Der Wire-Layer unterscheidet damit „Sig-Pruefung
  /// fehlgeschlagen" (Anker vorhanden → droppen, kein Nachfassen noetig) von
  /// „konnte gar nicht geprueft werden" (kein Anker → AUTH_RETRIEVE anstossen).
  bool hasAnchorFor(Uint8List userId) => _anchorFor(userId) != null;

  LivenessRecord? getLiveness(Uint8List userId, Uint8List deviceNodeId) {
    final key = '${bytesToHex(userId)}:${bytesToHex(deviceNodeId)}';
    return _storedLiveness[key];
  }

  // ── Device-KEM-Record API (Welle 5, §4.3) ─────────────────────

  /// Wird vom Wire-Layer aufgerufen wenn IDENTITY_KEM_PUBLISH ankommt.
  /// Trust-Anchor: ed25519_sig vom User-Master-Key. Sig-Verification erfolgt
  /// im Wire-Layer (cleona_node.dart) bevor wir hier landen — derselbe
  /// Pattern wie bei AuthManifest/Liveness.
  bool handleKemPublish(DeviceKemRecord r) {
    // D1: mit verankertem AuthManifest muss der embedded userEd25519Pk dem
    // Anker entsprechen UND die Sig gegen ihn verifizieren (schliesst den
    // selbstreferenziellen Check). Ohne Anker: Transition-Verhalten.
    //
    // §7.1.4: die Anker-Bindung des eingebetteten userEd25519Pk gilt in
    // BEIDEN Pfaden — auch ein delegiert signierter Record behauptet weiter,
    // zu diesem User zu gehoeren. Nur die Sig-Pruefung selbst laeuft dann
    // ueber die Zertifikatskette.
    final anchorManifest = _anchorManifestFor(r.userId);
    if (anchorManifest != null) {
      final anchor = anchorManifest.userEd25519Pk;
      if (!_pkEqual(r.userEd25519Pk, anchor) ||
          !r.verifyAnchored(anchorManifest)) {
        return false;
      }
    }
    final key = '${bytesToHex(r.userId)}:${bytesToHex(r.deviceId)}';
    final existing = _storedKemRecords[key];
    if (existing != null && r.sequenceNumber <= existing.sequenceNumber) {
      return false;
    }
    _storedKemRecords[key] = r;
    _enforceKemCap();
    _persistAsync();
    return true;
  }

  /// D1: verankerter User-Pk aus dem gespeicherten AuthManifest (nur wenn
  /// es embedded Keys traegt — die wurden bei handleAuthPublish verifiziert).
  Uint8List? _anchorFor(Uint8List userId) =>
      _anchorManifestFor(userId)?.userEd25519Pk;

  /// D1 + §7.1.4: das verankernde AuthManifest selbst. Die delegierte
  /// Signaturkette braucht BEIDE User-Pks — das Delegationszertifikat ist
  /// hybrid signiert (§7.1.1), eine reine Ed25519-Pruefung waere genau die
  /// Abkuerzung, die eine gefaelschte Delegation billig macht.
  ///
  /// P6: sie braucht ausserdem das Zertifikat selbst, das seit P6 nicht mehr
  /// im Record steckt, sondern in `deviceDelegations` dieses Manifests. Damit
  /// ist das ganze Manifest — nicht nur sein Pk — der Anker.
  AuthManifest? _anchorManifestFor(Uint8List userId) {
    final m = _storedAuthManifests[bytesToHex(userId)];
    return (m != null && m.hasEmbeddedKeys) ? m : null;
  }

  static bool _pkEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  DeviceKemRecord? getKemRecord(Uint8List userId, Uint8List deviceId) {
    final key = '${bytesToHex(userId)}:${bytesToHex(deviceId)}';
    return _storedKemRecords[key];
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

  void _enforceKemCap() {
    if (_storedKemRecords.length <= maxKemRecords) return;
    final entries = _storedKemRecords.entries.toList();
    entries.sort((a, b) {
      // Key-Format ist "userIdHex:deviceIdHex"; XOR-Dist auf userIdHex
      // (gleiche Logik wie Liveness-Cap; eviktiert die fernsten User-IDs).
      final aUserId = hexToBytes(a.key.split(':')[0]);
      final bUserId = hexToBytes(b.key.split(':')[0]);
      return _xorDistance(bUserId).compareTo(_xorDistance(aUserId));
    });
    final toEvict = entries.length - maxKemRecords;
    for (var i = 0; i < toEvict; i++) {
      _storedKemRecords.remove(entries[i].key);
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
    _storedKemRecords.removeWhere((_, r) => r.isExpired());
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

    final kems = (data['kemRecords'] as List?) ?? [];
    for (final entry in kems) {
      try {
        final bytes = hexToBytes(entry as String);
        final r = DeviceKemRecord.fromProto(
            proto.DeviceKemRecordV3.fromBuffer(bytes));
        if (!r.isExpired()) {
          final key = '${bytesToHex(r.userId)}:${bytesToHex(r.deviceId)}';
          _storedKemRecords[key] = r;
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
    try {
      fileEncryption!.writeJsonFile(storagePath!, {
        'authManifests': _storedAuthManifests.values
            .map((m) => bytesToHex(Uint8List.fromList(m.toProto().writeToBuffer())))
            .toList(),
        'liveness': _storedLiveness.values
            .map((r) => bytesToHex(Uint8List.fromList(r.toProto().writeToBuffer())))
            .toList(),
        'kemRecords': _storedKemRecords.values
            .map((r) => bytesToHex(Uint8List.fromList(r.toProto().writeToBuffer())))
            .toList(),
      });
    } catch (e) {
      stderr.writeln('[IdentityDhtHandler] _persistNow failed (non-fatal): $e');
    }
  }

  // ── Test/Debug helpers ────────────────────────────────────────

  int get authManifestCount => _storedAuthManifests.length;
  int get livenessCount => _storedLiveness.length;
  int get kemRecordCount => _storedKemRecords.length;

  /// Direct access to the in-memory auth-manifest store; used by tests
  /// that need to inject pre-built (e.g. expired) records to exercise prune.
  @visibleForTesting
  Map<String, AuthManifest> get debugAuthManifests => _storedAuthManifests;

  @visibleForTesting
  Map<String, LivenessRecord> get debugLiveness => _storedLiveness;

  @visibleForTesting
  Map<String, DeviceKemRecord> get debugKemRecords => _storedKemRecords;
}
