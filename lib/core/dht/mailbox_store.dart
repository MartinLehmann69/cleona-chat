import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/peer_info.dart';
import 'package:cleona/core/platform/disk_space.dart';

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
    final messageId = Uint8List.fromList(bytes.sublist(offset, offset + 32));
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

/// Persistent fragment store for relay and own mailbox.
/// Fragments stored as binary files (.bin) in the profile mailbox directory.
/// Migrates legacy .json files on load.
class MailboxStore {
  final String profileDir;
  final CLogger _log;
  final Map<String, StoredFragment> _fragments = {};
  Timer? _flushTimer;
  Timer? _pruneTimer;
  bool _dirty = false;

  /// Total relay storage budget in bytes.
  /// Dynamically set based on available device storage.
  int _totalBudget = 500 * 1024 * 1024; // 500 MB default

  /// Max fraction of total budget for a single source.
  static const double perSourceFraction = 0.20; // 20%

  /// Min/max bounds for total budget.
  static const int minBudget = 100 * 1024 * 1024;  // 100 MB
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
        _totalBudget = (freeBytes * diskFraction).toInt().clamp(minBudget, maxBudget);
        _log.info('Storage budget: ${(_totalBudget / (1024 * 1024)).round()} MB '
            '(${(diskFraction * 100).round()}% of ${(freeBytes / (1024 * 1024)).round()} MB free)');
      } else {
        // Fallback: keep current budget (500 MB default)
        _totalBudget = _totalBudget.clamp(minBudget, maxBudget);
      }
    } catch (_) {
      _totalBudget = minBudget;
    }
  }

  /// Current total relay storage budget in bytes.
  int get totalBudget => _totalBudget;

  /// Set the total budget explicitly (e.g. from platform-specific disk query).
  set totalBudget(int bytes) {
    _totalBudget = bytes.clamp(minBudget, maxBudget);
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
      _deleteFragmentFile(key);
    }
    return expired.length;
  }

  /// Store a fragment (relay or own).
  /// Returns true if stored, false if rejected (dedup, budget exceeded).
  bool storeFragment(StoredFragment fragment) {
    final key = fragment.storeKey;
    if (_fragments.containsKey(key)) return false; // Dedup

    // Budget check: total
    final currentTotal = totalRelayBytes;
    if (currentTotal + fragment.diskSize > _totalBudget) {
      _log.debug('Fragment rejected: total budget exceeded '
          '(${currentTotal ~/ 1024}KB + ${fragment.diskSize ~/ 1024}KB > ${_totalBudget ~/ 1024}KB)');
      return false;
    }

    // Budget check: per-source
    final perSourceMax = (_totalBudget * perSourceFraction).toInt();
    final sourceBytes = _bytesForSource(fragment.mailboxId);
    if (sourceBytes + fragment.diskSize > perSourceMax) {
      _log.debug('Fragment rejected: per-source budget exceeded for '
          '${bytesToHex(fragment.mailboxId).substring(0, 8)}');
      return false;
    }

    _fragments[key] = fragment;
    _dirty = true;
    return true;
  }

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
      _deleteFragmentFile(key);
    }
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
