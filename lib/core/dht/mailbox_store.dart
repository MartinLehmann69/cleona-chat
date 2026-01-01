import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/peer_info.dart';
import 'package:cleona/core/platform/disk_space.dart';

/// Result of a fragment store attempt (3-valued: stored, duplicate, rejected).
enum FragmentStoreResult { stored, duplicateIdentical, rejected }

/// Stored fragment entry.
class StoredFragment {
  final Uint8List mailboxId;
  final Uint8List messageId;
  final int fragmentIndex;
  final int totalFragments;
  final int requiredFragments;
  final Uint8List data;
  final int originalSize;
  final DateTime storedAt;
  final DateTime expiresAt;

  StoredFragment({
    required this.mailboxId,
    required this.messageId,
    required this.fragmentIndex,
    required this.totalFragments,
    required this.requiredFragments,
    required this.data,
    required this.originalSize,
    DateTime? storedAt,
    DateTime? expiresAt,
  })  : storedAt = storedAt ?? DateTime.now(),
        expiresAt = expiresAt ?? DateTime.now().add(const Duration(days: 7));

  String get storeKey =>
      '${bytesToHex(mailboxId)}:${bytesToHex(messageId)}:$fragmentIndex';

  /// Size in bytes on disk (binary format).
  int get diskSize => _binHeaderSize + data.length;

  // ── Binary serialization ─────────────────────────────────────────
  // Header: [32B mailboxId][32B messageId][4B fragIdx][4B totalFrags]
  //         [4B reqFrags][4B origSize][8B storedAt ms][8B expiresAt ms]
  // Total header: 96 bytes. Followed by raw fragment data.
  static const int _binHeaderSize = 96;

  /// Serialize to binary (header + raw data).
  Uint8List toBinary() {
    final buf = ByteData(_binHeaderSize + data.length);
    var offset = 0;

    // mailboxId (32 bytes)
    for (var i = 0; i < 32; i++) {
      buf.setUint8(offset + i, i < mailboxId.length ? mailboxId[i] : 0);
    }
    offset += 32;

    // messageId (32 bytes, zero-padded if shorter)
    for (var i = 0; i < 32; i++) {
      buf.setUint8(offset + i, i < messageId.length ? messageId[i] : 0);
    }
    offset += 32;

    buf.setUint32(offset, fragmentIndex, Endian.big); offset += 4;
    buf.setUint32(offset, totalFragments, Endian.big); offset += 4;
    buf.setUint32(offset, requiredFragments, Endian.big); offset += 4;
    buf.setUint32(offset, originalSize, Endian.big); offset += 4;
    buf.setInt64(offset, storedAt.millisecondsSinceEpoch, Endian.big); offset += 8;
    buf.setInt64(offset, expiresAt.millisecondsSinceEpoch, Endian.big); offset += 8;

    // Fragment data
    final result = buf.buffer.asUint8List();
    result.setRange(_binHeaderSize, _binHeaderSize + data.length, data);
    return result;
  }

  /// Deserialize from binary.
  static StoredFragment? fromBinary(Uint8List bytes) {
    if (bytes.length < _binHeaderSize) return null;
    final buf = ByteData.sublistView(bytes);
    var offset = 0;

    final mailboxId = Uint8List.fromList(bytes.sublist(offset, offset + 32));
    offset += 32;
    final rawMessageId = bytes.sublist(offset, offset + 32);
    var msgLen = 32;
    while (msgLen > 16 && rawMessageId[msgLen - 1] == 0) {
      msgLen--;
    }
    final messageId = Uint8List.fromList(rawMessageId.sublist(0, msgLen));
    offset += 32;

    final fragmentIndex = buf.getUint32(offset, Endian.big); offset += 4;
    final totalFragments = buf.getUint32(offset, Endian.big); offset += 4;
    final requiredFragments = buf.getUint32(offset, Endian.big); offset += 4;
    final originalSize = buf.getUint32(offset, Endian.big); offset += 4;
    final storedAtMs = buf.getInt64(offset, Endian.big); offset += 8;
    final expiresAtMs = buf.getInt64(offset, Endian.big); offset += 8;

    final data = Uint8List.fromList(bytes.sublist(_binHeaderSize));

    return StoredFragment(
      mailboxId: mailboxId,
      messageId: messageId,
      fragmentIndex: fragmentIndex,
      totalFragments: totalFragments,
      requiredFragments: requiredFragments,
      data: data,
      originalSize: originalSize,
      storedAt: DateTime.fromMillisecondsSinceEpoch(storedAtMs),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAtMs),
    );
  }

  // ── Legacy JSON (read-only, for migration) ───────────────────────
  static StoredFragment fromJson(Map<String, dynamic> json) => StoredFragment(
        mailboxId: hexToBytes(json['mailboxId'] as String),
        messageId: hexToBytes(json['messageId'] as String),
        fragmentIndex: json['fragmentIndex'] as int,
        totalFragments: json['totalFragments'] as int,
        requiredFragments: json['requiredFragments'] as int,
        data: base64Decode(json['data'] as String),
        originalSize: json['originalSize'] as int,
        storedAt: DateTime.fromMillisecondsSinceEpoch(json['storedAt'] as int),
        expiresAt: DateTime.fromMillisecondsSinceEpoch(json['expiresAt'] as int),
      );
}

/// In-memory push state for proactive fragment push (Architecture §3.5).
/// Tracks per-fragment delivery state to the mailbox owner so that a relay
/// can retry on no-ACK within the 3-attempt budget. Reachability events do
/// not trigger fresh push series (V3.1.75 §3.5 "No re-push on reachability").
/// Not persisted: rebuilt on relay-node restart from current reachability —
/// restart resets the budget exactly once (architectural exception).
/// Duplicate pushes after a restart are deduplicated by `MailboxStore.storeFragment`.
class FragmentPushState {
  final Uint8List ownerNodeId;
  int attempts = 0;
  DateTime? lastPushAt;
  bool pushAcked = false;
  /// Active retry timer — cancelled on ACK or when max attempts reached.
  /// Single timer per (storeKey, owner) ensures idempotent retry chain.
  Timer? retryTimer;
  FragmentPushState(this.ownerNodeId);

  void cancelRetry() {
    retryTimer?.cancel();
    retryTimer = null;
  }
}

/// Persistent fragment store for relay and own mailbox.
/// Fragments stored as binary files (.bin) in the profile mailbox directory.
/// Migrates legacy .json files on load.
class MailboxStore {
  final String profileDir;
  final CLogger _log;
  final Map<String, StoredFragment> _fragments = {};
  /// In-memory push state per storeKey. See `FragmentPushState`.
  final Map<String, FragmentPushState> _pushState = {};
  Timer? _flushTimer;
  Timer? _pruneTimer;
  bool _dirty = false;

  /// Max push attempts per fragment before giving up proactive push.
  /// (Architecture §3.5 — same semantics as §3.3.7 maxPushCount.)
  static const int maxPushAttempts = 3;

  /// Fragment TTL for DHT-stored Reed-Solomon fragments (7 days).
  /// Matches `StoredFragment` default `expiresAt` (line 32 above).
  /// (Architecture §6.3 — Store-and-Forward / Reed-Solomon backup window.)
  static const Duration fragmentTtl = Duration(days: 7);

  /// Total relay storage budget in bytes.
  /// Dynamically set based on available device storage.
  int _totalBudget = 500 * 1024 * 1024; // 500 MB default

  /// Max fraction of total budget for a single source.
  static const double perSourceFraction = 0.20; // 20%

  /// Max bound for total budget.
  static const int maxBudget = 2 * 1024 * 1024 * 1024; // 2 GB

  /// Fraction of free disk space to use for relay storage.
  static const double diskFraction = 0.10; // 10%

  MailboxStore({required this.profileDir})
      : _log = CLogger.get('mailbox', profileDir: profileDir);

  /// Load fragments from disk (binary + legacy JSON migration).
  Future<void> load() async {
    final dir = Directory('$profileDir/mailbox');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
      await _updateBudget();
      _startFlushTimer();
      _startPruneTimer();
      return;
    }

    final files = dir.listSync().whereType<File>();
    var loaded = 0;
    var expired = 0;
    var migrated = 0;
    final now = DateTime.now();

    for (final file in files) {
      try {
        StoredFragment? frag;

        if (file.path.endsWith('.bin')) {
          frag = StoredFragment.fromBinary(file.readAsBytesSync());
        } else if (file.path.endsWith('.json')) {
          // Legacy migration: read JSON, will be saved as .bin on next flush
          final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
          frag = StoredFragment.fromJson(json);
          migrated++;
        } else {
          continue;
        }

        if (frag == null) continue;

        if (frag.expiresAt.isBefore(now)) {
          file.deleteSync();
          expired++;
          continue;
        }
        _fragments[frag.storeKey] = frag;
        loaded++;

        // Delete legacy JSON after successful load (will be saved as .bin)
        if (file.path.endsWith('.json')) {
          file.deleteSync();
          _dirty = true;
        }
      } catch (e) {
        _log.debug('Failed to load fragment ${file.path}: $e');
      }
    }

    if (migrated > 0) {
      _log.info('Migrated $migrated legacy JSON fragments to binary');
    }
    _log.info('Loaded $loaded fragments ($expired expired)');
    await _updateBudget();
    _startFlushTimer();
    _startPruneTimer();
  }

  void _startFlushTimer() {
    _flushTimer = Timer.periodic(const Duration(seconds: 2), (_) => _flush());
  }

  void _startPruneTimer() {
    _pruneTimer = Timer.periodic(const Duration(hours: 1), (_) async {
      final count = pruneExpired();
      if (count > 0) _log.info('Pruned $count expired fragments');
      await _updateBudget(); // Refresh budget based on current free space
    });
  }

  /// Update relay storage budget based on available disk space.
  /// Async: queries free disk space via platform-specific API.
  Future<void> _updateBudget() async {
    try {
      final freeBytes = await DiskSpace.getFreeDiskSpace(profileDir);
      if (freeBytes > 0) {
        final desiredBudget = (freeBytes * diskFraction).toInt();
        final safeCap = (freeBytes * 0.50).toInt();
        _totalBudget = desiredBudget.clamp(0, maxBudget);
        if (_totalBudget > safeCap) _totalBudget = safeCap;
        if (freeBytes < 50 * 1024 * 1024) {
          _totalBudget = 0;
          _log.warn('Free disk critically low (${(freeBytes / (1024 * 1024)).round()} MB) — relay storage disabled');
        }
        _log.info('Storage budget: ${(_totalBudget / (1024 * 1024)).round()} MB '
            '(${(diskFraction * 100).round()}% of ${(freeBytes / (1024 * 1024)).round()} MB free)');
      } else {
        _totalBudget = 0;
      }
    } catch (_) {
      _totalBudget = 0;
    }
  }

  /// Current total relay storage budget in bytes.
  int get totalBudget => _totalBudget;

  /// Set the total budget explicitly (e.g. from platform-specific disk query).
  set totalBudget(int bytes) {
    _totalBudget = bytes.clamp(0, maxBudget);
  }

  /// Total bytes used by all stored fragments.
  int get totalRelayBytes {
    var total = 0;
    for (final f in _fragments.values) {
      total += f.diskSize;
    }
    return total;
  }

  /// Bytes used by fragments from a specific source (mailboxId).
  int _bytesForSource(Uint8List mailboxId) {
    var total = 0;
    for (final f in _fragments.values) {
      if (_bytesEqual(f.mailboxId, mailboxId)) {
        total += f.diskSize;
      }
    }
    return total;
  }

  /// Remove expired fragments from memory and disk.
  int pruneExpired() {
    final now = DateTime.now();
    final expired = <String>[];
    for (final entry in _fragments.entries) {
      if (entry.value.expiresAt.isBefore(now)) {
        expired.add(entry.key);
      }
    }
    for (final key in expired) {
      _fragments.remove(key);
      _pushState.remove(key)?.cancelRetry();
      _deleteFragmentFile(key);
    }
    return expired.length;
  }

  /// Store a fragment (relay or own).
  /// Returns [FragmentStoreResult.stored] on success,
  /// [FragmentStoreResult.duplicateIdentical] if the same key+data already exists,
  /// [FragmentStoreResult.rejected] on generation conflict or budget exceeded.
  FragmentStoreResult storeFragment(StoredFragment fragment) {
    final key = fragment.storeKey;
    if (_fragments.containsKey(key)) {
      final existing = _fragments[key]!;
      if (existing.data.length == fragment.data.length &&
          _bytesEqual(existing.data, fragment.data)) {
        return FragmentStoreResult.duplicateIdentical;
      }
      return FragmentStoreResult.rejected; // generation conflict
    }

    // Budget check: total
    final currentTotal = totalRelayBytes;
    if (currentTotal + fragment.diskSize > _totalBudget) {
      _log.debug('Fragment rejected: total budget exceeded '
          '(${currentTotal ~/ 1024}KB + ${fragment.diskSize ~/ 1024}KB > ${_totalBudget ~/ 1024}KB)');
      return FragmentStoreResult.rejected;
    }

    // Budget check: per-source
    final perSourceMax = (_totalBudget * perSourceFraction).toInt();
    final sourceBytes = _bytesForSource(fragment.mailboxId);
    if (sourceBytes + fragment.diskSize > perSourceMax) {
      _log.debug('Fragment rejected: per-source budget exceeded for '
          '${bytesToHex(fragment.mailboxId).substring(0, 8)}');
      return FragmentStoreResult.rejected;
    }

    _fragments[key] = fragment;
    _dirty = true;
    return FragmentStoreResult.stored;
  }

  /// Retrieve a single stored fragment by its storeKey.
  StoredFragment? retrieveByKey(String storeKey) => _fragments[storeKey];

  /// Retrieve all fragments for a mailbox ID (byte comparison).
  List<StoredFragment> retrieveFragments(Uint8List mailboxId) {
    return _fragments.values
        .where((f) => _bytesEqual(f.mailboxId, mailboxId))
        .toList();
  }

  /// Retrieve fragments for a specific message ID.
  List<StoredFragment> getFragmentsForMessage(Uint8List messageId) {
    return _fragments.values
        .where((f) => _bytesEqual(f.messageId, messageId))
        .toList();
  }

  /// Delete all fragments for a mailbox+message combination.
  void deleteFragments(Uint8List mailboxId, Uint8List messageId) {
    final keysToRemove = <String>[];
    for (final entry in _fragments.entries) {
      if (_bytesEqual(entry.value.mailboxId, mailboxId) &&
          _bytesEqual(entry.value.messageId, messageId)) {
        keysToRemove.add(entry.key);
      }
    }
    for (final key in keysToRemove) {
      _fragments.remove(key);
      _pushState.remove(key)?.cancelRetry();
      _deleteFragmentFile(key);
    }
  }

  // ── Proactive push state (Architecture §3.5) ──────────────────────

  /// Get or create push state for a fragment + owner.
  /// Returns null if fragment is no longer stored.
  FragmentPushState? pushStateFor(String storeKey, Uint8List ownerNodeId) {
    if (!_fragments.containsKey(storeKey)) return null;
    var state = _pushState[storeKey];
    if (state == null || !_bytesEqual(state.ownerNodeId, ownerNodeId)) {
      state = FragmentPushState(Uint8List.fromList(ownerNodeId));
      _pushState[storeKey] = state;
    }
    return state;
  }

  /// Mark a push attempt (increments counter, records timestamp).
  void recordPushAttempt(String storeKey, Uint8List ownerNodeId) {
    final state = pushStateFor(storeKey, ownerNodeId);
    if (state == null) return;
    state.attempts++;
    state.lastPushAt = DateTime.now();
  }

  /// Mark a fragment as ACKed by the owner. Looks up by messageId+index.
  /// Cancels any pending retry timer. Returns the storeKey if found, else null.
  String? markPushAcked(Uint8List messageId, int fragmentIndex) {
    for (final entry in _fragments.entries) {
      final f = entry.value;
      if (f.fragmentIndex == fragmentIndex &&
          _bytesEqual(f.messageId, messageId)) {
        final state = _pushState[entry.key];
        if (state != null) {
          state.pushAcked = true;
          state.cancelRetry();
        }
        return entry.key;
      }
    }
    return null;
  }

  /// Reset push budget for a specific storeKey so it can be re-attempted.
  /// Used by the §5.4 V3.1.138 re-arm-on-owner-reappearance mechanism.
  void resetPushBudget(String storeKey) {
    final state = _pushState[storeKey];
    if (state == null) return;
    if (state.pushAcked) return;
    state.cancelRetry();
    state.attempts = 0;
    state.lastPushAt = null;
  }

  /// Fragments whose push is stalled (never started, stranded mid-chain,
  /// or budget exhausted) and not ACKed — candidates for re-arm when the
  /// owner (re)appears. Excludes live chains (active retry timer).
  List<MapEntry<String, FragmentPushState>> rearmablePushEntries() {
    return _pushState.entries
        .where((e) => !e.value.pushAcked &&
            !(e.value.retryTimer?.isActive ?? false) &&
            _fragments.containsKey(e.key))
        .toList();
  }

  /// Pending pushes (not acked, attempts < max) for a specific owner.
  /// Diagnostic / test inspection only — production wiring no longer triggers
  /// re-pushes on reachability changes (V3.1.75 §3.5).
  List<StoredFragment> pendingPushesFor(Uint8List ownerNodeId) {
    final result = <StoredFragment>[];
    for (final entry in _fragments.entries) {
      final state = _pushState[entry.key];
      if (state == null) continue;
      if (state.pushAcked) continue;
      if (state.attempts >= maxPushAttempts) continue;
      if (!_bytesEqual(state.ownerNodeId, ownerNodeId)) continue;
      result.add(entry.value);
    }
    return result;
  }

  void _deleteFragmentFile(String key) {
    final safeName = key.replaceAll(':', '_');
    // Delete both formats (migration cleanup)
    for (final ext in ['.bin', '.json']) {
      final file = File('$profileDir/mailbox/$safeName$ext');
      if (file.existsSync()) {
        try {
          file.deleteSync();
        } catch (_) {}
      }
    }
  }

  void _flush() {
    if (!_dirty) return;
    _dirty = false;

    final dir = Directory('$profileDir/mailbox');
    if (!dir.existsSync()) dir.createSync(recursive: true);

    for (final entry in _fragments.entries) {
      final safeName = entry.key.replaceAll(':', '_');
      final file = File('${dir.path}/$safeName.bin');
      if (!file.existsSync()) {
        try {
          file.writeAsBytesSync(entry.value.toBinary());
        } catch (e) {
          _log.debug('Failed to write fragment: $e');
        }
      }
    }
  }

  /// Number of stored fragments.
  int get fragmentCount => _fragments.length;

  /// Total bytes of stored fragment data (actual measurement, not estimate).
  int get totalStoredBytes => _fragments.values.fold<int>(0, (sum, f) => sum + f.data.length);

  /// Budget utilization as fraction (0.0 – 1.0).
  double get budgetUtilization =>
      _totalBudget > 0 ? totalRelayBytes / _totalBudget : 0.0;

  void dispose() {
    _flushTimer?.cancel();
    _pruneTimer?.cancel();
    for (final s in _pushState.values) {
      s.cancelRetry();
    }
    _flush();
  }
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
