import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/crypto/file_encryption.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/network/clogger.dart';

/// §26.6.2 Paket C — Retry-Pfad fuer Emergency Key Rotation.
///
/// Background: `rotateIdentityKeys()` sends a dual-signed
/// `KEY_ROTATION_BROADCAST` to every accepted contact and hopes the contacts
/// confirm via `KEY_ROTATION_ACK`. The initial broadcast is stored in S&F for
/// 30d (V3.1.67, commit e916e36), but a contact who stays offline longer
/// (extended trip, device swap, dead battery holiday) would still miss the
/// rotation and from then on be unreachable — any message encrypted with the
/// new keys cannot be decrypted by a contact that still has the old keys.
///
/// This manager persists per-contact retry state and re-sends the original
/// dual-signed broadcast when a contact has not ACKed within `retryIntervalMs`.
///
/// Key invariants:
///
/// - Only one rotation state at a time. A new rotation supersedes any prior
///   state (the previous broadcast's keys are already history).
/// - The stored broadcast bytes are the *inner* `KeyRotationBroadcast`
///   protobuf which is dual-signed with the OLD and NEW Ed25519 keys. The
///   outer envelope and KEM ciphertext are recreated per retry — only the
///   inner signature matters for the receiver's `_handleEmergencyKeyRotation`
///   verification path.
/// - After `rotatedAt + expireTtlMs` the pending contact list is flushed
///   into `expired`. Expired contacts are NOT auto-removed — the user must
///   decide what to do. We emit an IPC event so the UI can warn.
/// - The manager never retries an `acked` or `expired` contact. A contact
///   that rotates away independently (different rotation epoch) will simply
///   time out here and land in `expired`.
class KeyRotationRetryManager {
  final String profileDir;
  final String identityId;
  final FileEncryption? _fileEnc;
  final CLogger _log;

  /// Retry cadence. Caller ticks the timer; this class decides what is due.
  final int retryIntervalMs;

  /// Absolute cutoff for a single rotation state (default 90d).
  final int expireTtlMs;

  /// Max number of retry attempts per contact (default 3). After this, the
  /// contact moves to `expired` even if the overall window is not yet hit.
  final int maxAttempts;

  KeyRotationRetryState? _state;

  bool _loaded = false;

  KeyRotationRetryManager({
    required this.profileDir,
    required this.identityId,
    FileEncryption? fileEnc,
    this.retryIntervalMs = 24 * 60 * 60 * 1000,
    this.expireTtlMs = 90 * 24 * 60 * 60 * 1000,
    this.maxAttempts = 3,
  })  : _fileEnc = fileEnc,
        _log = CLogger.get('key-rotation-retry[$identityId]');

  // ── Persistence ─────────────────────────────────────────────────────────

  void load() {
    if (_fileEnc == null) {
      _loaded = true;
      return;
    }
    try {
      final json = _fileEnc.readJsonFile('$profileDir/key_rotation_retry.json');
      if (json != null) {
        _state = KeyRotationRetryState.fromJson(json);
        _log.info('Loaded rotation state ${_state!.rotationId.substring(0, 8)} '
            'pending=${_state!.pending.length} '
            'acked=${_state!.acked.length} '
            'expired=${_state!.expired.length}');
      }
    } catch (e) {
      _log.warn('Failed to load key rotation retry state: $e');
    }
    _loaded = true;
  }

  void _save() {
    if (_fileEnc == null) return;
    if (!_loaded) {
      _log.warn('REFUSED to save key rotation retry — load may have failed');
      return;
    }
    try {
      if (_state == null) {
        // Nothing to persist yet; writeJsonFile of empty is fine but avoid
        // overwriting a prior non-empty file.
        return;
      }
      _fileEnc.writeJsonFile(
          '$profileDir/key_rotation_retry.json', _state!.toJson());
    } catch (e) {
      _log.warn('Failed to save key rotation retry state: $e');
    }
  }

  // ── State queries ───────────────────────────────────────────────────────

  /// True if there is an active rotation state with at least one pending
  /// contact that has not ACKed or expired yet.
  bool get hasActiveRotation =>
      _state != null && _state!.pending.isNotEmpty;

  /// Read-only snapshot for IPC events / tests.
  KeyRotationRetryState? get state => _state;

  int get pendingCount => _state?.pending.length ?? 0;
  int get ackedCount => _state?.acked.length ?? 0;
  int get expiredCount => _state?.expired.length ?? 0;

  // ── Mutation ────────────────────────────────────────────────────────────

  /// Called by `rotateIdentityKeys()` once the initial broadcast has been
  /// sent. Replaces any previous state (new rotation supersedes).
  ///
  /// `broadcastBytes` must be the serialized `KeyRotationBroadcast` protobuf
  /// including both signature fields. `contactNodeIdsHex` is the list of
  /// contacts the initial broadcast was sent to (they count as attempt 1).
  /// `oldUserIdHex` is the sender's pre-rotation user-id hex; every retry
  /// sets `envelope.senderId` to this value so the offline receiver's
  /// contact-lookup (`_contacts[senderHex]`) still hits before it has had
  /// a chance to apply the rotation.
  void startNewRotation({
    required Uint8List broadcastBytes,
    required Iterable<String> contactNodeIdsHex,
    required String oldUserIdHex,
    required int now,
  }) {
    final rotationId = _randomRotationId();
    final pending = <String, KeyRotationRetryEntry>{};
    for (final hex in contactNodeIdsHex) {
      pending[hex] = KeyRotationRetryEntry(
        firstAttemptAt: now,
        lastAttemptAt: now,
        attempts: 1,
      );
    }
    _state = KeyRotationRetryState(
      rotationId: rotationId,
      rotatedAt: now,
      expireAt: now + expireTtlMs,
      maxAttempts: maxAttempts,
      oldUserIdHex: oldUserIdHex,
      broadcastBytes: Uint8List.fromList(broadcastBytes),
      pending: pending,
      acked: <String>{},
      expired: <String>{},
    );
    _save();
    _log.info('Started rotation ${rotationId.substring(0, 8)} '
        'pending=${pending.length} expireAt=${_state!.expireAt}');
  }

  /// An ACK arrived. Mark contact as acked (idempotent).
  /// Returns true if state changed.
  bool markAcked(String contactNodeIdHex) {
    final s = _state;
    if (s == null) return false;
    final removed = s.pending.remove(contactNodeIdHex) != null;
    s.expired.remove(contactNodeIdHex);
    final wasNew = s.acked.add(contactNodeIdHex);
    if (removed || wasNew) {
      _save();
      return true;
    }
    return false;
  }

  /// Returns the list of contacts due for a retry right now. A contact is due
  /// if it is in `pending`, `lastAttemptAt + retryIntervalMs <= now`, and
  /// neither `maxAttempts` nor `expireAt` has been reached. Contacts whose
  /// limits are already exceeded are moved to `expired` as a side effect.
  ///
  /// Returns the `broadcastBytes` plus the list of contact hexes the caller
  /// should re-send to. The caller must invoke [markAttempt] after each
  /// successful re-send.
  DueRetries duePending({required int now}) {
    final s = _state;
    if (s == null) {
      return DueRetries(
        broadcastBytes: Uint8List(0),
        oldUserIdHex: '',
        contacts: const [],
      );
    }

    final due = <String>[];
    final toExpire = <String>[];

    s.pending.forEach((hex, entry) {
      if (now >= s.expireAt) {
        toExpire.add(hex);
        return;
      }
      if (entry.attempts >= s.maxAttempts) {
        toExpire.add(hex);
        return;
      }
      if (now - entry.lastAttemptAt >= retryIntervalMs) {
        due.add(hex);
      }
    });

    if (toExpire.isNotEmpty) {
      for (final hex in toExpire) {
        s.pending.remove(hex);
        if (s.expired.add(hex)) {
          s.pendingExpiredNotifications.add(hex);
        }
      }
      _log.warn('Marked ${toExpire.length} contact(s) as expired '
          '(no ACK after ${s.maxAttempts} attempts or $expireTtlMs ms)');
      _save();
    }

    return DueRetries(
      broadcastBytes: s.broadcastBytes,
      oldUserIdHex: s.oldUserIdHex,
      contacts: List.unmodifiable(due),
    );
  }

  /// Record that a retry was sent for [contactNodeIdHex] at [now].
  void markAttempt(String contactNodeIdHex, {required int now}) {
    final s = _state;
    if (s == null) return;
    final entry = s.pending[contactNodeIdHex];
    if (entry == null) return;
    entry.lastAttemptAt = now;
    entry.attempts++;
    _save();
  }

  /// Test-only: reset all `lastAttemptAt` to 0 so the next `duePending` call
  /// treats every pending contact as due, regardless of `retryIntervalMs`.
  /// Used by E2E harness to simulate "24h passed" without wall-clock wait.
  /// Does NOT reset the `attempts` counter — `maxAttempts` still caps retries
  /// as in production.
  void resetAttemptClocksForTesting() {
    final s = _state;
    if (s == null) return;
    for (final entry in s.pending.values) {
      entry.lastAttemptAt = 0;
    }
    _save();
  }

  /// Drops the whole state. Only called when the identity itself is deleted.
  /// The on-disk file is removed so a subsequent `load()` cannot resurrect
  /// stale rotation pending/expired sets.
  void clear() {
    _state = null;
    if (_fileEnc != null) {
      final plain = File('$profileDir/key_rotation_retry.json');
      final encrypted = File('$profileDir/key_rotation_retry.json.enc');
      for (final f in [plain, encrypted]) {
        try {
          if (f.existsSync()) f.deleteSync();
        } catch (e) {
          _log.warn('Failed to delete ${f.path}: $e');
        }
      }
    }
  }

  /// Contacts that have been newly moved to expired since the last call.
  /// Caller uses this to emit IPC events exactly once per transition.
  List<String> drainNewlyExpired() {
    final s = _state;
    if (s == null) return const [];
    if (s.pendingExpiredNotifications.isEmpty) return const [];
    final out = List<String>.unmodifiable(s.pendingExpiredNotifications);
    s.pendingExpiredNotifications.clear();
    _save();
    return out;
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  /// 8-byte random id encoded as 16 hex chars. Purely a local tombstone so
  /// we can tell one rotation apart from the next in logs and tests —
  /// security does not depend on it, but we use the CSPRNG for consistency
  /// with the rest of the codebase.
  static String _randomRotationId() {
    final bytes = SodiumFFI().randomBytes(8);
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}

/// Result of [KeyRotationRetryManager.duePending].
class DueRetries {
  final Uint8List broadcastBytes;
  /// Pre-rotation user-id hex of the rotator. Retry envelopes must use this
  /// as `senderId` so the offline receiver's `_contacts[senderHex]` lookup
  /// succeeds. Empty when the manager has no active rotation.
  final String oldUserIdHex;
  final List<String> contacts;
  DueRetries({
    required this.broadcastBytes,
    required this.oldUserIdHex,
    required this.contacts,
  });
}

/// Per-contact retry bookkeeping.
class KeyRotationRetryEntry {
  int firstAttemptAt;
  int lastAttemptAt;
  int attempts;

  KeyRotationRetryEntry({
    required this.firstAttemptAt,
    required this.lastAttemptAt,
    required this.attempts,
  });

  Map<String, dynamic> toJson() => {
        'firstAttemptAt': firstAttemptAt,
        'lastAttemptAt': lastAttemptAt,
        'attempts': attempts,
      };

  factory KeyRotationRetryEntry.fromJson(Map<String, dynamic> json) =>
      KeyRotationRetryEntry(
        firstAttemptAt: (json['firstAttemptAt'] as num).toInt(),
        lastAttemptAt: (json['lastAttemptAt'] as num).toInt(),
        attempts: (json['attempts'] as num).toInt(),
      );
}

/// Top-level rotation state. Serialized as JSON with the broadcast payload in
/// base64.
class KeyRotationRetryState {
  String rotationId;
  int rotatedAt;
  int expireAt;
  int maxAttempts;
  /// Pre-rotation user-id hex of the rotator (us). See `DueRetries`.
  String oldUserIdHex;
  Uint8List broadcastBytes;
  Map<String, KeyRotationRetryEntry> pending;
  Set<String> acked;
  Set<String> expired;

  /// Contacts that became expired since the last IPC event drain.
  List<String> pendingExpiredNotifications;

  KeyRotationRetryState({
    required this.rotationId,
    required this.rotatedAt,
    required this.expireAt,
    required this.maxAttempts,
    required this.oldUserIdHex,
    required this.broadcastBytes,
    required this.pending,
    required this.acked,
    required this.expired,
    List<String>? pendingExpiredNotifications,
  }) : pendingExpiredNotifications =
            pendingExpiredNotifications ?? <String>[];

  Map<String, dynamic> toJson() => {
        'rotationId': rotationId,
        'rotatedAt': rotatedAt,
        'expireAt': expireAt,
        'maxAttempts': maxAttempts,
        'oldUserIdHex': oldUserIdHex,
        'broadcastBytes': base64Encode(broadcastBytes),
        'pending': pending.map((k, v) => MapEntry(k, v.toJson())),
        'acked': acked.toList(),
        'expired': expired.toList(),
        'pendingExpiredNotifications': pendingExpiredNotifications,
      };

  factory KeyRotationRetryState.fromJson(Map<String, dynamic> json) {
    final pendingJson = json['pending'] as Map<String, dynamic>? ?? {};
    final pending = <String, KeyRotationRetryEntry>{};
    pendingJson.forEach((k, v) {
      pending[k] =
          KeyRotationRetryEntry.fromJson(v as Map<String, dynamic>);
    });
    return KeyRotationRetryState(
      rotationId: json['rotationId'] as String,
      rotatedAt: (json['rotatedAt'] as num).toInt(),
      expireAt: (json['expireAt'] as num).toInt(),
      maxAttempts: (json['maxAttempts'] as num).toInt(),
      oldUserIdHex: json['oldUserIdHex'] as String? ?? '',
      broadcastBytes:
          Uint8List.fromList(base64Decode(json['broadcastBytes'] as String)),
      pending: pending,
      acked: Set<String>.from(
          (json['acked'] as List?)?.cast<String>() ?? const <String>[]),
      expired: Set<String>.from(
          (json['expired'] as List?)?.cast<String>() ?? const <String>[]),
      pendingExpiredNotifications: List<String>.from(
          (json['pendingExpiredNotifications'] as List?)
                  ?.cast<String>() ??
              const <String>[]),
    );
  }
}
