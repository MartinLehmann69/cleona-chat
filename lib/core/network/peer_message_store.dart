import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/peer_info.dart';
import 'package:cleona/core/storage/atomic_json_writer.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;

/// Outer `NetworkPacketV3.senderDeviceId` embedded in a stored envelope, or
/// `null` if the bytes don't parse (defensive — every store site writes
/// canonical `NetworkPacketV3` bytes, so a parse failure here means
/// corrupted/foreign data, not a normal case).
///
/// §7.1 P3: this is the "Merkmal aus dem Inhalt" that distinguishes a
/// device's own placed message from someone else's — `PeerRetrieve.
/// requesterNodeId` alone cannot: before Linked-Device pairing completes,
/// both devices derive the identical userId from the shared seed, so a
/// requesting device retrieving its OWN just-placed message looks
/// byte-identical, at the `requesterNodeId` level, to the intended
/// recipient device retrieving it. The outer sender-device-id is unencrypted
/// (needed for routing before KEM-decap) and is authored per-device, so it
/// is the one field that tells the two apart.
Uint8List? _envelopeSenderDeviceId(Uint8List wrappedEnvelope) {
  try {
    final pkt = proto.NetworkPacketV3.fromBuffer(wrappedEnvelope);
    final sd = pkt.senderDeviceId;
    return sd.isEmpty ? null : Uint8List.fromList(sd);
  } catch (_) {
    return null;
  }
}

String _sha256Hex(Uint8List data) =>
    bytesToHex(SodiumFFI().sha256(data));

/// A single held message for Store-and-Forward delivery.
class _HeldMessage {
  final String storeIdHex;
  final String envelopeHashHex;
  final Uint8List wrappedEnvelope;
  final DateTime storedAt;
  final DateTime expiresAt;

  /// Last time this message was pushed via S&F proactive push.
  /// Null = never pushed. Used for rate-limiting pushes.
  DateTime? lastPushedAt;

  /// How many times this message has been pushed.
  /// After maxPushCount, the message stays in store (for PEER_RETRIEVE / TTL)
  /// but is no longer eligible for proactive push — prevents endless flooding.
  int pushCount = 0;

  /// When this message was first retrieved via PEER_RETRIEVE. Non-null means
  /// the recipient has requested it; after a grace window the message is
  /// garbage-collected by [PeerMessageStore.pruneExpired].
  DateTime? _retrievedAt;

  /// Correlates a [PeerMessageStore.peekRetrievable] call with the matching
  /// [PeerMessageStore.markRetrieved] across the `await` on the transport.
  ///
  /// Deliberately NOT persisted (absent from toJson/fromJson): the stamp is
  /// only meaningful for a PEER_RETRIEVE_RESPONSE that is in flight right now,
  /// and a daemon restart aborts every in-flight delivery anyway. Persisting it
  /// would resurrect a stamp whose send can no longer complete, so the first
  /// markRetrieved after a restart could mark messages that were never sent.
  DateTime? _retrieveAttemptAt;

  _HeldMessage({
    required this.storeIdHex,
    required this.envelopeHashHex,
    required this.wrappedEnvelope,
    required this.storedAt,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Map<String, dynamic> toJson() => {
    'storeId': storeIdHex,
    'envelopeHash': envelopeHashHex,
    'envelope': base64Encode(wrappedEnvelope),
    'storedAt': storedAt.millisecondsSinceEpoch,
    'expiresAt': expiresAt.millisecondsSinceEpoch,
    // Persist push-rate-limit state across daemon restarts. Without this the
    // pushCount/lastPushedAt reset to 0/null on every restart, so a held
    // message gets 3 new push cycles per restart → excess traffic + amplifies
    // Bug #R2 (recipient conv-dedup). Only serialized when >0/non-null to
    // keep JSON tidy for fresh messages.
    if (pushCount > 0) 'pushCount': pushCount,
    if (lastPushedAt != null) 'lastPushedAt': lastPushedAt!.millisecondsSinceEpoch,
    if (_retrievedAt != null) 'retrievedAt': _retrievedAt!.millisecondsSinceEpoch,
  };

  static _HeldMessage fromJson(Map<String, dynamic> json) {
    final envelope = base64Decode(json['envelope'] as String);
    final m = _HeldMessage(
      storeIdHex: json['storeId'] as String,
      envelopeHashHex: (json['envelopeHash'] as String?) ?? _sha256Hex(envelope),
      wrappedEnvelope: envelope,
      storedAt: DateTime.fromMillisecondsSinceEpoch(json['storedAt'] as int),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(json['expiresAt'] as int),
    );
    m.pushCount = (json['pushCount'] as int?) ?? 0;
    final lpa = json['lastPushedAt'] as int?;
    if (lpa != null) m.lastPushedAt = DateTime.fromMillisecondsSinceEpoch(lpa);
    final ra = json['retrievedAt'] as int?;
    if (ra != null) m._retrievedAt = DateTime.fromMillisecondsSinceEpoch(ra);
    return m;
  }
}

/// Store-and-Forward message store.
///
/// Holds whole messages (not fragments) for offline recipients.
/// Messages are stored by recipient nodeId and retrieved when the
/// recipient comes online and sends a PEER_RETRIEVE.
class PeerMessageStore {
  /// Max messages per recipient (budget, §5.5).
  static const maxMessagesPerRecipient = 30;

  /// Max size per wrapped envelope (12 KB).
  /// L3 Redesign: S&F only for messages ≤10 KB canonical; 12 KB envelope
  /// allows for KEM+signature overhead. Larger payloads use Erasure Coding.
  static const maxEnvelopeSize = 12 * 1024;

  /// Default TTL: 7 days.
  static const defaultTtlMs = 7 * 24 * 60 * 60 * 1000;

  /// Global limits across all recipients.
  static const maxTotalMessages = 3000;
  static const maxTotalBytes = 100 * 1024 * 1024;

  /// Grace window after PEER_RETRIEVE before messages are garbage-collected.
  /// Protects against UDP loss: a second retrieve within this window still
  /// returns the messages.
  static const _retrieveGraceMs = 60 * 1000;

  final String _profileDir;
  final CLogger _log;

  /// recipientUserIdHex → list of held messages.
  final Map<String, List<_HeldMessage>> _messages = {};

  /// Known store IDs for dedup.
  final Set<String> _knownStoreIds = {};

  /// Known envelope content hashes for dedup (same content, different storeId).
  final Set<String> _knownEnvelopeHashes = {};

  bool _dirty = false;
  Timer? _flushTimer;

  /// Serializes concurrent _flush() calls within-process.
  Future<void>? _writeInFlight;

  PeerMessageStore({required String profileDir})
      : _profileDir = profileDir,
        _log = CLogger.get('peer-msg-store', profileDir: profileDir);

  /// Load held messages from disk.
  Future<void> load() async {
    final path = '$_profileDir/peer_messages.json';
    // Sidecar-recovery via AtomicJsonWriter: handles canonical + .tmp + .old.
    final json = AtomicJsonWriter.readJsonFile(path);
    if (json == null) {
      _startFlushTimer();
      return;
    }

    try {
      for (final entry in json.entries) {
        final recipientHex = entry.key;
        final msgs = (entry.value as List).map((e) {
          try {
            return _HeldMessage.fromJson(e as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        }).whereType<_HeldMessage>().where((m) => !m.isExpired).toList();

        if (msgs.isNotEmpty) {
          _messages[recipientHex] = msgs;
          for (final m in msgs) {
            _knownStoreIds.add(m.storeIdHex);
            _knownEnvelopeHashes.add(m.envelopeHashHex);
          }
        }
      }
      _log.info('Loaded ${_messages.values.fold<int>(0, (s, l) => s + l.length)} held messages');
    } catch (e) {
      _log.error('Failed to load peer messages: $e');
    }

    _startFlushTimer();
  }

  /// Store a message for a recipient.
  ///
  /// Returns true if stored, false if rejected (budget, size, dedup).
  bool storeMessage({
    required Uint8List recipientUserId,
    required Uint8List wrappedEnvelope,
    required String storeIdHex,
    int ttlMs = defaultTtlMs,
  }) {
    if (ttlMs <= 0 || ttlMs > defaultTtlMs) ttlMs = defaultTtlMs;

    // Size check
    if (wrappedEnvelope.length > maxEnvelopeSize) {
      _log.debug('PEER_STORE rejected: envelope too large (${wrappedEnvelope.length} bytes)');
      return false;
    }

    // StoreId dedup — idempotent ACK: return true so sender sees success
    if (_knownStoreIds.contains(storeIdHex)) {
      _log.debug('PEER_STORE dedup (idempotent ACK): $storeIdHex');
      return true;
    }

    // Envelope-hash dedup: same content under different storeId
    final envelopeHash = _sha256Hex(wrappedEnvelope);
    if (_knownEnvelopeHashes.contains(envelopeHash)) {
      _log.debug('PEER_STORE dedup (envelope hash): $envelopeHash');
      return true;
    }

    final recipientHex = bytesToHex(recipientUserId);
    final list = _messages.putIfAbsent(recipientHex, () => []);

    // Per-recipient budget: oldest-first eviction per §5.5
    if (list.length >= maxMessagesPerRecipient) {
      final evicted = list.removeAt(0);
      _knownStoreIds.remove(evicted.storeIdHex);
      _knownEnvelopeHashes.remove(evicted.envelopeHashHex);
      _log.debug('PEER_STORE evicted oldest for ${recipientHex.substring(0, 8)} '
          '(${list.length}/$maxMessagesPerRecipient)');
    }

    // Global limits
    final totalMsgs = _messages.values.fold<int>(0, (s, l) => s + l.length);
    if (totalMsgs >= maxTotalMessages) {
      _log.debug('PEER_STORE rejected: global message limit reached ($totalMsgs)');
      return false;
    }
    final totalBytes = _messages.values.fold<int>(0,
        (sum, list) => sum + list.fold<int>(0, (s, m) => s + m.wrappedEnvelope.length));
    if (totalBytes + wrappedEnvelope.length > maxTotalBytes) {
      _log.debug('PEER_STORE rejected: global byte limit reached ($totalBytes bytes)');
      return false;
    }

    list.add(_HeldMessage(
      storeIdHex: storeIdHex,
      envelopeHashHex: envelopeHash,
      wrappedEnvelope: Uint8List.fromList(wrappedEnvelope),
      storedAt: DateTime.now(),
      expiresAt: DateTime.now().add(Duration(milliseconds: ttlMs)),
    ));
    _knownStoreIds.add(storeIdHex);
    _knownEnvelopeHashes.add(envelopeHash);
    _dirty = true;

    _log.debug('Stored message $storeIdHex for ${recipientHex.substring(0, 8)} '
        '(${list.length}/$maxMessagesPerRecipient)');
    return true;
  }

  /// Retrieve all messages for a recipient.
  ///
  /// §5.5: marks messages as retrieved and schedules deferred deletion
  /// after [_retrieveGraceMs]. The grace window protects against UDP loss:
  /// if the PEER_RETRIEVE_RESPONSE is lost, a second retrieve within the
  /// window still returns the messages. After the window, messages are
  /// garbage-collected by [pruneExpired].
  List<Uint8List> retrieveMessages(Uint8List recipientUserId) {
    final recipientHex = bytesToHex(recipientUserId);
    final list = _messages[recipientHex];
    if (list == null || list.isEmpty) return [];

    final now = DateTime.now();
    final result = <Uint8List>[];
    for (final m in list) {
      if (m.isExpired) continue;
      result.add(m.wrappedEnvelope);
      m._retrievedAt ??= now;
    }
    if (result.isNotEmpty) _dirty = true;
    _log.info('Retrieved ${result.length} messages for '
        '${recipientHex.substring(0, 8)} (deferred delete in ${_retrieveGraceMs ~/ 1000}s)');
    return result;
  }

  /// Return envelopes eligible for retrieve WITHOUT marking them, stamping
  /// each selected message with [attemptAt]. The caller must call
  /// [markRetrieved] with the SAME [attemptAt] after a successful send.
  ///
  /// S300 — the stamp is what keeps the peek/mark split exact across the
  /// `await sendInfraTo` that sits between the two calls. Without it
  /// [markRetrieved] swept every non-expired message of the recipient,
  /// including one that a PEER_STORE arriving during the send had just added
  /// (`handleIncomingPeerStoreInfra` runs in the same event loop between the
  /// microtasks). That message never travelled in the response, yet carried
  /// `_retrievedAt` and was deleted by [pruneExpired] after the 60s grace —
  /// a silent loss. Same mechanism as [peekMessages]/[commitPushAttempt].
  ///
  /// [excludeSenderDeviceId], when given, skips (neither returns nor stamps)
  /// any held message whose outer `NetworkPacketV3.senderDeviceId` equals it
  /// — §7.1 P3: a device must never retrieve back a message it authored
  /// itself. This matters for the shared pre-pairing mailbox (`sendToUser`
  /// §7.2 LD-11 bootstrap): the requesting device's own general S&F poll can
  /// reach a peer holding the copy it just placed for its future twin, and
  /// `requesterNodeId` is identical on both devices before pairing — so it
  /// cannot serve as the distinguishing signal (see
  /// [_envelopeSenderDeviceId]). Passing the caller's own device is correct
  /// unconditionally, not just for pairing: no device legitimately retrieves
  /// content it authored. Excluded here (pre-stamp) rather than filtered
  /// post-hoc, so a skipped message is not spuriously marked retrieved by
  /// the matching [markRetrieved] call.
  List<Uint8List> peekRetrievable(Uint8List recipientUserId, {
    required DateTime attemptAt,
    Uint8List? excludeSenderDeviceId,
  }) {
    final recipientHex = bytesToHex(recipientUserId);
    final list = _messages[recipientHex];
    if (list == null || list.isEmpty) return [];
    final result = <Uint8List>[];
    for (final m in list) {
      if (m.isExpired) continue;
      if (excludeSenderDeviceId != null) {
        final authorDeviceId = _envelopeSenderDeviceId(m.wrappedEnvelope);
        if (authorDeviceId != null &&
            bytesToHex(authorDeviceId) == bytesToHex(excludeSenderDeviceId)) {
          continue;
        }
      }
      m._retrieveAttemptAt = attemptAt;
      result.add(m.wrappedEnvelope);
    }
    return result;
  }

  /// Mark exactly those messages as retrieved that the matching
  /// [peekRetrievable] call stamped with [attemptAt].
  /// Called after a successful send of the PEER_RETRIEVE_RESPONSE.
  ///
  /// Correlating on the timestamp rather than on the returned envelopes keeps
  /// the two calls exact across the `await` in between: a message stored
  /// during the send carries no stamp and is not marked, and a concurrent
  /// retrieve carries a different stamp.
  ///
  /// `_retrievedAt ??= now` stays: the 60s grace window (a lost RESPONSE must
  /// still be answerable by a second retrieve) is measured from the FIRST
  /// retrieve, so a repeat retrieve must not extend the deletion window.
  void markRetrieved(Uint8List recipientUserId, DateTime attemptAt) {
    final recipientHex = bytesToHex(recipientUserId);
    final list = _messages[recipientHex];
    if (list == null) return;
    final now = DateTime.now();
    var count = 0;
    for (final m in list) {
      if (m.isExpired) continue;
      if (m._retrieveAttemptAt != attemptAt) continue;
      m._retrievedAt ??= now;
      count++;
    }
    if (count > 0) _dirty = true;
  }

  /// Peek at stored messages for a recipient WITHOUT removing them.
  ///
  /// Returns only messages that haven't been pushed recently (rate-limited
  /// to once per [pushIntervalSeconds] per message, max [maxPushCount] times).
  /// After maxPushCount pushes, the message is no longer eligible for proactive
  /// push but stays in store for PEER_RETRIEVE or TTL expiry.
  ///
  /// Architecture: S&F messages persist until confirmed delivery (PEER_RETRIEVE)
  /// or TTL expiry (7 days). Push is event-driven (peer comes online) and
  /// rate-limited + count-limited to prevent flooding.
  /// Selects pushable messages and stamps them with [attemptAt] so a
  /// concurrent push cannot pick the same message again while this one is
  /// still in flight.
  ///
  /// S299 — the push BUDGET is deliberately not consumed here. It used to be
  /// (`pushCount++` sat right next to `lastPushedAt = now`), while the caller
  /// discarded the transport result. Field measurement on Node2 showed what
  /// that costs: `_buildInfraPacket` drops any KEM-path message to a device
  /// whose Device-KEM record is missing and `sendInfraTo` returns false —
  /// 6415 such drops across nine message types, 87 of them exactly this
  /// `PEER_RETRIEVE_RESPONSE`. Each one burned one of three push attempts
  /// against a packet that never left the machine, and the budget is
  /// persisted, so after three drops the message was unreachable by push for
  /// the rest of its 7-day TTL. Call [commitPushAttempt] with the same
  /// [attemptAt] once the transport reported success.
  ///
  /// The timestamp stamp stays unconditional on purpose: a failed attempt
  /// should not be retried immediately. The dominant failure here is a
  /// persistent condition (no KEM record), so re-attempting before the next
  /// interval would spin without any chance of succeeding.
  List<Uint8List> peekMessages(Uint8List recipientUserId, {
    int pushIntervalSeconds = 300,
    int maxPushCount = 3,
    DateTime? attemptAt,
  }) {
    final recipientHex = bytesToHex(recipientUserId);
    final list = _messages[recipientHex];
    if (list == null || list.isEmpty) return [];

    final now = attemptAt ?? DateTime.now();
    final interval = Duration(seconds: pushIntervalSeconds);
    final result = <Uint8List>[];

    for (final m in list) {
      if (m.isExpired) continue;
      if (m.pushCount >= maxPushCount) continue;
      if (m.lastPushedAt != null && now.difference(m.lastPushedAt!) < interval) continue;
      m.lastPushedAt = now;
      result.add(m.wrappedEnvelope);
    }

    if (result.isNotEmpty) _dirty = true;
    return result;
  }

  /// Consumes one push-budget unit for every message stamped with
  /// [attemptAt] by the matching [peekMessages] call. Returns how many
  /// messages were charged.
  ///
  /// Call this only after the transport actually succeeded. Correlating on
  /// the timestamp rather than on the returned envelopes keeps the two calls
  /// exact across the `await` in between: a message stored during the send
  /// carries no stamp and is not charged, and a concurrent push carries a
  /// different stamp.
  int commitPushAttempt(Uint8List recipientUserId, DateTime attemptAt) {
    final list = _messages[bytesToHex(recipientUserId)];
    if (list == null || list.isEmpty) return 0;
    var charged = 0;
    for (final m in list) {
      if (m.lastPushedAt == attemptAt) {
        m.pushCount++;
        charged++;
      }
    }
    if (charged > 0) _dirty = true;
    return charged;
  }

  /// Check if we have messages for a given recipient.
  bool hasMessagesFor(Uint8List recipientUserId) {
    final recipientHex = bytesToHex(recipientUserId);
    final list = _messages[recipientHex];
    return list != null && list.isNotEmpty;
  }

  /// All recipient userIdHex values that have undelivered messages.
  Iterable<String> get recipientUserIds =>
      _messages.entries
          .where((e) => e.value.any((m) =>
              !m.isExpired && m._retrievedAt == null))
          .map((e) => e.key);

  /// Remove expired and retrieved-past-grace messages.
  int pruneExpired() {
    var pruned = 0;
    final emptyKeys = <String>[];
    final now = DateTime.now();

    for (final entry in _messages.entries) {
      final before = entry.value.length;
      entry.value.removeWhere((m) {
        final shouldRemove = m.isExpired ||
            (m._retrievedAt != null &&
                now.difference(m._retrievedAt!).inMilliseconds >
                    _retrieveGraceMs);
        if (shouldRemove) {
          _knownStoreIds.remove(m.storeIdHex);
          _knownEnvelopeHashes.remove(m.envelopeHashHex);
          return true;
        }
        return false;
      });
      pruned += before - entry.value.length;
      if (entry.value.isEmpty) emptyKeys.add(entry.key);
    }

    for (final key in emptyKeys) {
      _messages.remove(key);
    }

    if (pruned > 0) {
      _dirty = true;
      _log.debug('Pruned $pruned expired messages');
    }
    return pruned;
  }

  /// Total held messages across all recipients.
  int get totalMessages => _messages.values.fold<int>(0, (s, l) => s + l.length);

  /// Number of recipients with held messages.
  int get recipientCount => _messages.length;

  void _startFlushTimer() {
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(const Duration(seconds: 5), (_) => _flush());
  }

  Future<void> _flush() {
    if (!_dirty) return Future.value();
    _dirty = false;

    final prev = _writeInFlight;
    final myWrite = (() async {
      if (prev != null) {
        try {
          await prev;
        } catch (_) {}
      }
      try {
        final json = <String, dynamic>{};
        for (final entry in _messages.entries) {
          json[entry.key] = entry.value.map((m) => m.toJson()).toList();
        }
        AtomicJsonWriter.writeJsonFile('$_profileDir/peer_messages.json', json);
      } catch (e) {
        _log.error('Failed to flush peer messages: $e');
        _dirty = true;
      }
    })();
    _writeInFlight = myWrite;
    return myWrite;
  }

  Future<void> dispose() async {
    _flushTimer?.cancel();
    await _flush();
  }
}
