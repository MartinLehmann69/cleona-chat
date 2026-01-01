import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/peer_info.dart';

String _short(String s) => s.length >= 8 ? s.substring(0, 8) : s;

/// A queued message waiting for a route to become available.
class _QueuedMessage {
  final String messageIdHex;
  final Uint8List recipientNodeId;
  final Uint8List serializedEnvelope;
  final DateTime enqueuedAt;
  int retryCount;
  DateTime nextRetryAt;

  _QueuedMessage({
    required this.messageIdHex,
    required this.recipientNodeId,
    required this.serializedEnvelope,
    required this.enqueuedAt,
    this.retryCount = 0,
    DateTime? nextRetryAt,
  }) : nextRetryAt = nextRetryAt ?? DateTime.now();

  bool get isExpired =>
      DateTime.now().difference(enqueuedAt) > const Duration(days: 7);

  /// Exponential backoff: 5s → 15s → 45s → 2min → 5min cap.
  Duration get nextBackoff {
    const base = 5;
    const maxSeconds = 300; // 5 min
    final seconds = (base * _pow3(retryCount)).clamp(base, maxSeconds);
    return Duration(seconds: seconds);
  }

  static int _pow3(int exp) {
    var result = 1;
    for (var i = 0; i < exp; i++) {
      result *= 3;
      if (result > 300) return 300;
    }
    return result;
  }

  Map<String, dynamic> toJson() => {
    'messageId': messageIdHex,
    'recipientId': base64Encode(recipientNodeId),
    'envelope': base64Encode(serializedEnvelope),
    'enqueuedAt': enqueuedAt.millisecondsSinceEpoch,
    'retryCount': retryCount,
  };

  static _QueuedMessage? fromJson(Map<String, dynamic> json) {
    try {
      return _QueuedMessage(
        messageIdHex: json['messageId'] as String,
        recipientNodeId: base64Decode(json['recipientId'] as String),
        serializedEnvelope: base64Decode(json['envelope'] as String),
        enqueuedAt: DateTime.fromMillisecondsSinceEpoch(json['enqueuedAt'] as int),
        retryCount: json['retryCount'] as int? ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Message queue that holds outgoing messages when no route is available.
///
/// Messages are queued when sendEnvelope() cascade fails completely.
/// Queue is drained when:
/// - A new neighbor appears (DV routing update)
/// - A route to a queued destination becomes alive
/// - Periodic retry timer fires (30s)
class MessageQueue {
  /// Max messages per recipient.
  static const maxPerRecipient = 30;

  /// Max total queued messages.
  static const maxTotal = 200;

  /// Max envelope size (same as relay budget).
  static const maxEnvelopeSize = 300 * 1024;

  /// Max age before message is dropped.
  static const maxAge = Duration(days: 7);

  final String _profileDir;
  final CLogger _log;

  /// recipientNodeIdHex → queued messages.
  final Map<String, List<_QueuedMessage>> _queues = {};

  /// Dedup: known messageIds.
  final Set<String> _knownIds = {};

  /// Callback to attempt sending a queued message.
  /// Returns true if sent successfully (remove from queue).
  Future<bool> Function(Uint8List serializedEnvelope, Uint8List recipientNodeId)? onRetrySend;

  bool _dirty = false;
  Timer? _flushTimer;
  Timer? _retryTimer;

  MessageQueue({required String profileDir})
      : _profileDir = profileDir,
        _log = CLogger.get('msg-queue', profileDir: profileDir);

  /// Load queued messages from disk.
  Future<void> load() async {
    final file = File('$_profileDir/message_queue.json');
    if (!await file.exists()) return;

    try {
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      for (final entry in json.entries) {
        final recipientHex = entry.key;
        final msgs = (entry.value as List)
            .map((e) => _QueuedMessage.fromJson(e as Map<String, dynamic>))
            .whereType<_QueuedMessage>()
            .where((m) => !m.isExpired)
            .toList();

        if (msgs.isNotEmpty) {
          _queues[recipientHex] = msgs;
          for (final m in msgs) {
            _knownIds.add(m.messageIdHex);
          }
        }
      }
      final total = _queues.values.fold<int>(0, (s, l) => s + l.length);
      if (total > 0) {
        _log.info('Loaded $total queued messages for ${_queues.length} recipients');
      }
    } catch (e) {
      _log.error('Failed to load message queue: $e');
    }

    _startTimers();
  }

  /// Enqueue a message for later delivery.
  ///
  /// Returns true if queued, false if rejected (dedup, budget, size).
  bool enqueue({
    required String messageIdHex,
    required Uint8List recipientNodeId,
    required Uint8List serializedEnvelope,
  }) {
    if (serializedEnvelope.length > maxEnvelopeSize) {
      _log.debug('Queue rejected: envelope too large (${serializedEnvelope.length} bytes)');
      return false;
    }

    if (_knownIds.contains(messageIdHex)) {
      _log.debug('Queue rejected: duplicate $messageIdHex');
      return false;
    }

    final totalCount = _queues.values.fold<int>(0, (s, l) => s + l.length);
    if (totalCount >= maxTotal) {
      _log.debug('Queue rejected: total budget exceeded ($totalCount/$maxTotal)');
      return false;
    }

    final recipientHex = bytesToHex(recipientNodeId);
    final list = _queues.putIfAbsent(recipientHex, () => []);

    if (list.length >= maxPerRecipient) {
      _log.debug('Queue rejected: per-recipient budget for ${_short(recipientHex)}');
      return false;
    }

    list.add(_QueuedMessage(
      messageIdHex: messageIdHex,
      recipientNodeId: Uint8List.fromList(recipientNodeId),
      serializedEnvelope: Uint8List.fromList(serializedEnvelope),
      enqueuedAt: DateTime.now(),
    ));
    _knownIds.add(messageIdHex);
    _dirty = true;

    _log.info('Queued message ${_short(messageIdHex)} for '
        '${_short(recipientHex)} (${list.length}/$maxPerRecipient)');
    return true;
  }

  /// Remove a message from the queue (e.g. after DELIVERY_RECEIPT).
  bool remove(String messageIdHex) {
    if (!_knownIds.contains(messageIdHex)) return false;

    for (final list in _queues.values) {
      final idx = list.indexWhere((m) => m.messageIdHex == messageIdHex);
      if (idx >= 0) {
        list.removeAt(idx);
        _knownIds.remove(messageIdHex);
        _dirty = true;
        return true;
      }
    }
    _knownIds.remove(messageIdHex);
    return false;
  }

  /// Drain queued messages for a specific recipient.
  ///
  /// Called when a route to [recipientNodeIdHex] becomes available.
  Future<void> drainForRecipient(String recipientNodeIdHex) async {
    final list = _queues[recipientNodeIdHex];
    if (list == null || list.isEmpty) return;
    if (onRetrySend == null) return;

    _log.info('Draining ${list.length} queued messages for ${_short(recipientNodeIdHex)}');
    final toRemove = <_QueuedMessage>[];

    for (final msg in list) {
      if (msg.isExpired) {
        toRemove.add(msg);
        continue;
      }
      try {
        final ok = await onRetrySend!(msg.serializedEnvelope, msg.recipientNodeId);
        if (ok) {
          _log.info('Queue drain: delivered ${_short(msg.messageIdHex)}');
          toRemove.add(msg);
        } else {
          msg.retryCount++;
          msg.nextRetryAt = DateTime.now().add(msg.nextBackoff);
          _log.debug('Queue drain: retry failed for ${_short(msg.messageIdHex)}, '
              'next retry in ${msg.nextBackoff.inSeconds}s');
          break; // Stop draining — route may be flaky
        }
      } catch (e) {
        _log.error('Queue drain error: $e');
        break;
      }
    }

    for (final msg in toRemove) {
      list.remove(msg);
      _knownIds.remove(msg.messageIdHex);
    }

    if (list.isEmpty) _queues.remove(recipientNodeIdHex);
    if (toRemove.isNotEmpty) _dirty = true;
  }

  /// Drain all queued messages for any recipient that now has a route.
  ///
  /// Called when DV routing table changes.
  /// [hasRouteTo] returns true if a route exists for the given recipientHex.
  Future<void> drainAll(bool Function(String recipientHex) hasRouteTo) async {
    final recipientHexes = _queues.keys.toList();
    for (final hex in recipientHexes) {
      if (hasRouteTo(hex)) {
        await drainForRecipient(hex);
      }
    }
  }

  /// Periodic retry: attempts to send messages whose backoff has expired.
  Future<void> _retryExpiredBackoffs() async {
    if (onRetrySend == null) return;
    final now = DateTime.now();

    final recipientHexes = _queues.keys.toList();
    for (final hex in recipientHexes) {
      final list = _queues[hex];
      if (list == null || list.isEmpty) continue;

      final toRemove = <_QueuedMessage>[];
      for (final msg in list) {
        if (msg.isExpired) {
          toRemove.add(msg);
          continue;
        }
        if (now.isBefore(msg.nextRetryAt)) continue;

        try {
          final ok = await onRetrySend!(msg.serializedEnvelope, msg.recipientNodeId);
          if (ok) {
            toRemove.add(msg);
            _log.info('Queue retry: delivered ${_short(msg.messageIdHex)}');
          } else {
            msg.retryCount++;
            msg.nextRetryAt = now.add(msg.nextBackoff);
          }
        } catch (e) {
          _log.error('Queue retry error: $e');
        }
      }

      for (final msg in toRemove) {
        list.remove(msg);
        _knownIds.remove(msg.messageIdHex);
      }
      if (list.isEmpty) _queues.remove(hex);
      if (toRemove.isNotEmpty) _dirty = true;
    }
  }

  /// Prune expired messages.
  int pruneExpired() {
    var pruned = 0;
    final emptyKeys = <String>[];

    for (final entry in _queues.entries) {
      final before = entry.value.length;
      entry.value.removeWhere((m) {
        if (m.isExpired) {
          _knownIds.remove(m.messageIdHex);
          return true;
        }
        return false;
      });
      pruned += before - entry.value.length;
      if (entry.value.isEmpty) emptyKeys.add(entry.key);
    }

    for (final key in emptyKeys) {
      _queues.remove(key);
    }

    if (pruned > 0) {
      _dirty = true;
      _log.debug('Pruned $pruned expired queued messages');
    }
    return pruned;
  }

  /// Total queued messages.
  int get totalMessages => _queues.values.fold<int>(0, (s, l) => s + l.length);

  /// Number of recipients with queued messages.
  int get recipientCount => _queues.length;

  /// Check if a specific message is queued.
  bool contains(String messageIdHex) => _knownIds.contains(messageIdHex);

  void _startTimers() {
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(const Duration(seconds: 5), (_) => _flush());

    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(const Duration(seconds: 30), (_) => _retryExpiredBackoffs());
  }

  Future<void> _flush() async {
    if (!_dirty) return;
    _dirty = false;

    try {
      final json = <String, dynamic>{};
      for (final entry in _queues.entries) {
        json[entry.key] = entry.value.map((m) => m.toJson()).toList();
      }
      final file = File('$_profileDir/message_queue.json');
      await file.writeAsString(jsonEncode(json));
    } catch (e) {
      _log.error('Failed to flush message queue: $e');
      _dirty = true;
    }
  }

  Future<void> dispose() async {
    _flushTimer?.cancel();
    _retryTimer?.cancel();
    await _flush();
  }
}
