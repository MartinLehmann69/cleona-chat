import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/peer_info.dart';

/// A single held message for Store-and-Forward delivery.
class _HeldMessage {
  final String storeIdHex;
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

  _HeldMessage({
    required this.storeIdHex,
    required this.wrappedEnvelope,
    required this.storedAt,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Map<String, dynamic> toJson() => {
    'storeId': storeIdHex,
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
  };

  static _HeldMessage fromJson(Map<String, dynamic> json) {
    final m = _HeldMessage(
      storeIdHex: json['storeId'] as String,
      wrappedEnvelope: base64Decode(json['envelope'] as String),
      storedAt: DateTime.fromMillisecondsSinceEpoch(json['storedAt'] as int),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(json['expiresAt'] as int),
    );
    m.pushCount = (json['pushCount'] as int?) ?? 0;
    final lpa = json['lastPushedAt'] as int?;
    if (lpa != null) m.lastPushedAt = DateTime.fromMillisecondsSinceEpoch(lpa);
    return m;
  }
}

/// Store-and-Forward message store.
///
/// Holds whole messages (not fragments) for offline recipients.
/// Messages are stored by recipient nodeId and retrieved when the
/// recipient comes online and sends a PEER_RETRIEVE.
class PeerMessageStore {
  /// Max messages per recipient (budget).
  static const maxMessagesPerRecipient = 50;

  /// Max size per wrapped envelope (300 KB).
  /// V3.1.7: Raised from 100 KB to 300 KB to match relay payload limit —
  /// inline images (< 256 KB) stored as S&F backup during relay forwarding.
  static const maxEnvelopeSize = 300 * 1024;

  /// Default TTL: 7 days.
  static const defaultTtlMs = 7 * 24 * 60 * 60 * 1000;

  final String _profileDir;
  final CLogger _log;

  /// recipientNodeIdHex → list of held messages.
  final Map<String, List<_HeldMessage>> _messages = {};

  /// Known store IDs for dedup.
  final Set<String> _knownStoreIds = {};

  bool _dirty = false;
  Timer? _flushTimer;

  PeerMessageStore({required String profileDir})
      : _profileDir = profileDir,
        _log = CLogger.get('peer-msg-store', profileDir: profileDir);

  /// Load held messages from disk.
  Future<void> load() async {
    final file = File('$_profileDir/peer_messages.json');
    if (!await file.exists()) return;

    try {
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
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
    required Uint8List recipientNodeId,
    required Uint8List wrappedEnvelope,
    required String storeIdHex,
    int ttlMs = defaultTtlMs,
  }) {
    // Size check
    if (wrappedEnvelope.length > maxEnvelopeSize) {
      _log.debug('PEER_STORE rejected: envelope too large (${wrappedEnvelope.length} bytes)');
      return false;
    }

    // Dedup
    if (_knownStoreIds.contains(storeIdHex)) {
      _log.debug('PEER_STORE rejected: duplicate $storeIdHex');
      return false;
    }

    final recipientHex = bytesToHex(recipientNodeId);
    final list = _messages.putIfAbsent(recipientHex, () => []);

    // Budget
    if (list.length >= maxMessagesPerRecipient) {
      _log.debug('PEER_STORE rejected: budget exceeded for ${recipientHex.substring(0, 8)}');
      return false;
    }

    list.add(_HeldMessage(
      storeIdHex: storeIdHex,
      wrappedEnvelope: Uint8List.fromList(wrappedEnvelope),
      storedAt: DateTime.now(),
      expiresAt: DateTime.now().add(Duration(milliseconds: ttlMs)),
    ));
    _knownStoreIds.add(storeIdHex);
    _dirty = true;

    _log.debug('Stored message $storeIdHex for ${recipientHex.substring(0, 8)} '
        '(${list.length}/$maxMessagesPerRecipient)');
    return true;
  }

  /// Retrieve all messages for a recipient WITHOUT removing them.
  ///
  /// Multi-device: a second device with the same Node-ID may retrieve
  /// the same messages later. Messages expire via TTL (7 days) and
  /// are cleaned up by [pruneExpired].
  /// The recipient's deduplication layer discards already-processed messages.
  List<Uint8List> retrieveMessages(Uint8List recipientNodeId) {
    final recipientHex = bytesToHex(recipientNodeId);
    final list = _messages[recipientHex];
    if (list == null || list.isEmpty) return [];

    final result = list.where((m) => !m.isExpired).map((m) => m.wrappedEnvelope).toList();
    _log.info('Retrieved ${result.length} messages for ${recipientHex.substring(0, 8)} (non-destructive)');
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
  List<Uint8List> peekMessages(Uint8List recipientNodeId, {
    int pushIntervalSeconds = 300,
    int maxPushCount = 3,
  }) {
    final recipientHex = bytesToHex(recipientNodeId);
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

    return result;
  }

  /// Check if we have messages for a given recipient.
  bool hasMessagesFor(Uint8List recipientNodeId) {
    final recipientHex = bytesToHex(recipientNodeId);
    final list = _messages[recipientHex];
    return list != null && list.isNotEmpty;
  }

  /// Remove expired messages.
  int pruneExpired() {
    var pruned = 0;
    final emptyKeys = <String>[];

    for (final entry in _messages.entries) {
      final before = entry.value.length;
      entry.value.removeWhere((m) {
        if (m.isExpired) {
          _knownStoreIds.remove(m.storeIdHex);
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

  Future<void> _flush() async {
    if (!_dirty) return;
    _dirty = false;

    try {
      final json = <String, dynamic>{};
      for (final entry in _messages.entries) {
        json[entry.key] = entry.value.map((m) => m.toJson()).toList();
      }
      final file = File('$_profileDir/peer_messages.json');
      await file.writeAsString(jsonEncode(json));
    } catch (e) {
      _log.error('Failed to flush peer messages: $e');
      _dirty = true;
    }
  }

  Future<void> dispose() async {
    _flushTimer?.cancel();
    await _flush();
  }
}
