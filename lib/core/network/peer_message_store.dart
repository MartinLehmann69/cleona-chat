import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/peer_info.dart';
import 'package:cleona/core/storage/atomic_json_writer.dart';

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
  List<Uint8List> peekMessages(Uint8List recipientUserId, {
    int pushIntervalSeconds = 300,
    int maxPushCount = 3,
  }) {
    final recipientHex = bytesToHex(recipientUserId);
    final list = _messages[recipientHex];
    if (list == null || list.isEmpty) return [];

    final now = DateTime.now();
    final interval = Duration(seconds: pushIntervalSeconds);
    final result = <Uint8List>[];

    for (final m in list) {
      if (m.isExpired) continue;
      if (m.pushCount >= maxPushCount) continue;
      if (m.lastPushedAt != null && now.difference(m.lastPushedAt!) < interval) continue;
      m.lastPushedAt = now;
      m.pushCount++;
      result.add(m.wrappedEnvelope);
    }

    if (result.isNotEmpty) _dirty = true;
    return result;
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
