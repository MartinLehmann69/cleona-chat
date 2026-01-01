import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/log/clogger.dart';
import 'package:cleona/core/storage/message_store.dart';
import 'package:cleona/core/util/hex.dart';

/// Area of the rotation resubmission state in the store (formerly
/// `key_rotation_retry.json`), §26.6.2 package C.
const String kKeyRotationRetryArea = 'key_rotation_retry';

/// There is EXACTLY ONE rotation state — "a new rotation supersedes any
/// prior state", see class header. It therefore gets a fixed key and not
/// one formed from the `rotationId`: otherwise two states could lie side
/// by side, and the invariant would only be a declaration of intent.
const String kKeyRotationRetryKey = '_';

/// §26.6.2 package C — who has the emergency key rotation, and who not yet.
///
/// `rotateIdentityKeys()` sends a dual-signed `KEY_ROTATION_BROADCAST` to every
/// accepted contact; a contact confirms with `KEY_ROTATION_ACK`. This manager
/// keeps, per contact, whether it is still pending, has acknowledged, or will
/// not be reached.
///
/// **No clock, no counting (S408-LEBENSLAUF P20, finding A-7).** Until S408 a
/// 24-hour timer of the service counted "attempts" per contact — without
/// sending anything (the V4.1 carrier had fallen, gap G-3) — and moved a
/// contact to `expired` after three of them or 90 days. The broadcast is an
/// ordinary sending of the delivery layer: without a way it rests and leaves
/// again at every edge, placed it waits for the contact's collection, and
/// only after 14 days without a way does the delivery layer close it as
/// failed (§9.3, D-47; §11.3a: the layers above "do not repeat, count or
/// time anything themselves"). So the state follows the DELIVERY STATE of the
/// broadcast to each contact: pending → acked on its `KEY_ROTATION_ACK`,
/// pending → expired when the delivery layer closed that contact's broadcast
/// as failed ([markFailed]); the service reads it at its edges.
///
/// Key invariants:
///
/// - Only one rotation state at a time. A new rotation supersedes any prior
///   state (the previous broadcast's keys are already history).
/// - The stored broadcast bytes are the *inner* `KeyRotationBroadcast`
///   protobuf, dual-signed with the OLD and NEW Ed25519 keys.
/// - Expired contacts are NOT auto-removed — the user decides. An IPC event
///   lets the UI warn ([drainNewlyExpired]).
/// - The stored row keeps the fields an earlier 4.2 version reads
///   (`expireAt`, `maxAttempts`, the attempt fields), so a profile stays
///   readable by it (§1.2 principle 8, D-21); this version decides nothing
///   on them.
class KeyRotationRetryManager {
  final String profileDir;
  final String identityId;

  /// The encrypted store. `null` means proxy operation (the GUI via IPC):
  /// state machine without disk.
  final MessageStore? _store;
  final CLogger _log;

  KeyRotationRetryState? _state;

  bool _loaded = false;

  KeyRotationRetryManager({
    required this.profileDir,
    required this.identityId,
    this._store,
  })  : // profileDir is a constructor parameter (per identity) -> directly usable.
        _log = CLogger.get('key-rotation-retry[${shortHex(identityId)}]',
            profileDir: profileDir);

  // ── Persistence ─────────────────────────────────────────────────────────

  void load() {
    final store = _store;
    if (store == null) {
      _loaded = true;
      return;
    }
    try {
      // S366: ONE entry in the area `key_rotation_retry` instead of the
      // file of the same name.
      final json = store.loadArea(kKeyRotationRetryArea)[kKeyRotationRetryKey];
      if (json != null) {
        _state = KeyRotationRetryState.fromJson(json);
        _log.info('Loaded rotation state ${_state!.rotationId.substring(0, 8)} '
            'pending=${_state!.pending.length} '
            'acked=${_state!.acked.length} '
            'expired=${_state!.expired.length}');
      }
      // ONLY AFTER reading and NOT in the `catch`. Until S366 this
      // statement stood behind the `try` and thus ran ALSO after a read
      // error — the marker then said "loaded" although nothing was loaded,
      // and the latch below let the overwrite through.
      _loaded = true;
    } catch (e) {
      _log.warn('Failed to load key rotation retry state: $e');
    }
  }

  void _save() {
    final store = _store;
    if (store == null) return;
    // DATA-LOSS LATCH: it now asks the STORE, no longer only the load flag.
    //
    // The latch itself already stood here ("REFUSED to save key rotation
    // retry"), but it hung on a stand-in: `_loaded` was also set after a
    // read error (see [load]), and whether something lay on disk was never
    // checked. After the switch-over it would additionally have been
    // silently dead — the file it was about is never written again. It
    // fails closed if the store is not readable.
    if (!_loaded && _state == null) {
      var present = false;
      try {
        present = store.countArea(kKeyRotationRetryArea) > 0;
      } catch (e) {
        _log.warn('REFUSED to save key rotation retry — store not '
            'readable: $e');
        return;
      }
      if (present) {
        _log.warn('REFUSED to save key rotation retry — loading failed, '
            'but the storage holds a rotation state. '
            'Would cause data loss!');
        return;
      }
    }
    try {
      if (_state == null) {
        // Nothing to persist yet. Do NOT delete: [clear] is the path for
        // that, and it is only called on identity deletion.
        return;
      }
      // One object, one entry — `replaceArea` thus keeps the area at
      // exactly one row and clears old stock away too.
      store.replaceArea(
          kKeyRotationRetryArea, {kKeyRotationRetryKey: _state!.toJson()});
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
      // Read by an earlier 4.2 version only (class header); no decision here.
      expireAt: now + _earlierExpireMs,
      maxAttempts: _earlierMaxAttempts,
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

  /// The broadcast to [contactNodeIdHex] went out as the delivery layer's
  /// sending [messageIdHex] (the identifier of its outbound) — the one the
  /// service asks the delivery state of.
  void noteSending(String contactNodeIdHex, String messageIdHex) {
    final entry = _state?.pending[contactNodeIdHex];
    if (entry == null || entry.messageId == messageIdHex) return;
    entry.messageId = messageIdHex;
    _save();
  }

  /// The pending contacts with the sending their broadcast went out as.
  Map<String, String> get pendingSendings => {
        for (final e in _state?.pending.entries ??
            const <MapEntry<String, KeyRotationRetryEntry>>[])
          e.key: ?e.value.messageId,
      };

  /// The delivery layer closed the broadcast to [contactNodeIdHex] as
  /// failed (§9.3, D-47): the contact is not reached — `expired`, reported
  /// once ([drainNewlyExpired]). Returns true if the state changed.
  bool markFailed(String contactNodeIdHex) {
    final s = _state;
    if (s == null || s.pending.remove(contactNodeIdHex) == null) return false;
    if (s.expired.add(contactNodeIdHex)) {
      s.pendingExpiredNotifications.add(contactNodeIdHex);
    }
    _save();
    _log.warn('Rotation broadcast to ${shortHex(contactNodeIdHex)} closed as '
        'failed by the delivery layer — not reached');
    return true;
  }

  /// Drops the whole state. Only called when the identity itself is deleted.
  /// The stored row is removed so a subsequent `load()` cannot resurrect
  /// stale rotation pending/expired sets.
  void clear() {
    _state = null;
    final store = _store;
    if (store == null) return;
    try {
      store.replaceArea(kKeyRotationRetryArea, const {});
    } catch (e) {
      _log.warn('Failed to clear key rotation retry area: $e');
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

/// What an earlier 4.2 version reads from the row (class header).
const int _earlierExpireMs = 90 * 24 * 60 * 60 * 1000;
const int _earlierMaxAttempts = 3;

/// Per-contact retry bookkeeping.
class KeyRotationRetryEntry {
  /// Written for an earlier 4.2 version (class header); unused here.
  int firstAttemptAt;
  int lastAttemptAt;
  int attempts;

  /// The delivery layer's sending of the broadcast to this contact (its
  /// outbound identifier, hex); `null` until it is known, and in a row an
  /// earlier 4.2 version wrote.
  String? messageId;

  KeyRotationRetryEntry({
    required this.firstAttemptAt,
    required this.lastAttemptAt,
    required this.attempts,
    this.messageId,
  });

  Map<String, dynamic> toJson() => {
        'firstAttemptAt': firstAttemptAt,
        'lastAttemptAt': lastAttemptAt,
        'attempts': attempts,
        'messageId': ?messageId,
      };

  factory KeyRotationRetryEntry.fromJson(Map<String, dynamic> json) =>
      KeyRotationRetryEntry(
        firstAttemptAt: (json['firstAttemptAt'] as num).toInt(),
        lastAttemptAt: (json['lastAttemptAt'] as num).toInt(),
        attempts: (json['attempts'] as num).toInt(),
        messageId: json['messageId'] as String?,
      );
}

/// Top-level rotation state. Serialized as JSON with the broadcast payload in
/// base64.
class KeyRotationRetryState {
  String rotationId;
  int rotatedAt;
  int expireAt;
  int maxAttempts;
  /// Pre-rotation user-id hex of the rotator (us).
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
