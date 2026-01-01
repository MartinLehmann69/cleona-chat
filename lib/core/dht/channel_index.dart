import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cleona/core/crypto/sodium_ffi.dart' show SodiumFFI;
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/service/service_types.dart';

/// Local cache + DHT interface for public channel discovery.
///
/// DHT-Key for name uniqueness: SHA-256("channel-name:" + lowercase(name))
/// Local cache stores all known public channel entries for search.
class ChannelIndex {
  final String dataDir;
  final CLogger _log;

  /// In-memory cache of known public channels: channelIdHex -> entry.
  final Map<String, ChannelIndexEntry> _entries = {};

  /// Tracks when each entry was last updated locally.
  final Map<String, DateTime> _lastUpdated = {};

  bool _dirty = false;

  ChannelIndex({required this.dataDir, CLogger? log})
      : _log = log ?? CLogger('ChannelIndex');

  String get _cacheFile => '$dataDir/channel_index.json';

  // ── DHT Key derivation ──────────────────────────────────────────

  /// Compute the DHT key for a channel name (for uniqueness check).
  static Uint8List dhtKeyForName(String name) {
    final input = utf8.encode('channel-name:${name.toLowerCase().trim()}');
    return SodiumFFI().sha256(Uint8List.fromList(input));
  }

  /// Compute the DHT key for a channel ID (for index entry storage).
  static Uint8List dhtKeyForChannel(String channelIdHex) {
    final input = utf8.encode('channel-index:$channelIdHex');
    return SodiumFFI().sha256(Uint8List.fromList(input));
  }

  // ── Local cache management ──────────────────────────────────────

  void load() {
    final file = File(_cacheFile);
    if (!file.existsSync()) return;
    try {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final entries = json['entries'] as Map<String, dynamic>? ?? {};
      for (final e in entries.entries) {
        _entries[e.key] = ChannelIndexEntry.fromJson(e.value as Map<String, dynamic>);
        _lastUpdated[e.key] = DateTime.now();
      }
      _log.info('Loaded ${_entries.length} channel index entries');
    } catch (e) {
      _log.warn('Failed to load channel index: $e');
    }
  }

  void save() {
    if (!_dirty) return;
    try {
      Directory(dataDir).createSync(recursive: true);
      File(_cacheFile).writeAsStringSync(jsonEncode({
        'version': 1,
        'entries': _entries.map((k, v) => MapEntry(k, v.toJson())),
      }));
      _dirty = false;
    } catch (e) {
      _log.warn('Failed to save channel index: $e');
    }
  }

  /// Add or update an entry in the local cache.
  void upsert(ChannelIndexEntry entry) {
    final existing = _entries[entry.channelIdHex];
    // Only update if newer or more subscribers
    if (existing != null &&
        existing.subscriberCount >= entry.subscriberCount &&
        existing.badBadgeLevel == entry.badBadgeLevel) {
      return;
    }
    _entries[entry.channelIdHex] = entry;
    _lastUpdated[entry.channelIdHex] = DateTime.now();
    _dirty = true;
  }

  /// Remove a channel from the index (e.g. after deletion/tombstone).
  void remove(String channelIdHex) {
    _entries.remove(channelIdHex);
    _lastUpdated.remove(channelIdHex);
    _dirty = true;
  }

  /// Check if a channel name is taken in the local cache.
  bool isNameTaken(String name) {
    final lower = name.toLowerCase().trim();
    return _entries.values.any((e) => e.name.toLowerCase().trim() == lower);
  }

  /// Get entry by channel ID.
  ChannelIndexEntry? get(String channelIdHex) => _entries[channelIdHex];

  /// Get all cached entries.
  List<ChannelIndexEntry> get allEntries => _entries.values.toList();

  // ── Search ──────────────────────────────────────────────────────

  /// Search the local cache for matching channels.
  List<ChannelIndexEntry> search({
    String? query,
    String? language,
    bool includeAdult = false,
  }) {
    var results = _entries.values.toList();

    // Filter NSFW unless explicitly included
    if (!includeAdult) {
      results = results.where((e) => !e.isAdult).toList();
    }

    // Filter by language
    if (language != null && language != 'multi') {
      results = results.where((e) => e.language == language || e.language == 'multi').toList();
    }

    // Filter by query (case-insensitive substring match on name + description)
    if (query != null && query.isNotEmpty) {
      final q = query.toLowerCase();
      results = results.where((e) {
        return e.name.toLowerCase().contains(q) ||
            (e.description?.toLowerCase().contains(q) ?? false);
      }).toList();
    }

    // Filter tombstoned channels (permanent badge = level 3)
    results = results.where((e) => e.badBadgeLevel < 3).toList();

    // Sort: no badge first, then by subscriber count descending
    results.sort((a, b) {
      // Channels with badges sort lower
      if (a.badBadgeLevel != b.badBadgeLevel) {
        return a.badBadgeLevel.compareTo(b.badBadgeLevel);
      }
      return b.subscriberCount.compareTo(a.subscriberCount);
    });

    return results;
  }

  /// Serialize the full index for peer exchange (compact JSON).
  String serializeForExchange() {
    return jsonEncode(_entries.values.map((e) => e.toJson()).toList());
  }

  /// Merge entries received from a peer.
  int mergeFromExchange(String data) {
    try {
      final list = jsonDecode(data) as List<dynamic>;
      var added = 0;
      for (final item in list) {
        final entry = ChannelIndexEntry.fromJson(item as Map<String, dynamic>);
        if (!_entries.containsKey(entry.channelIdHex) ||
            _entries[entry.channelIdHex]!.subscriberCount < entry.subscriberCount) {
          _entries[entry.channelIdHex] = entry;
          _lastUpdated[entry.channelIdHex] = DateTime.now();
          added++;
        }
      }
      if (added > 0) _dirty = true;
      return added;
    } catch (e) {
      _log.warn('Failed to merge channel index: $e');
      return 0;
    }
  }

  /// Prune old entries (not updated for > 30 days).
  void prune({Duration maxAge = const Duration(days: 30)}) {
    final now = DateTime.now();
    final toRemove = <String>[];
    for (final e in _lastUpdated.entries) {
      if (now.difference(e.value) > maxAge) {
        toRemove.add(e.key);
      }
    }
    for (final key in toRemove) {
      _entries.remove(key);
      _lastUpdated.remove(key);
    }
    if (toRemove.isNotEmpty) {
      _dirty = true;
      _log.info('Pruned ${toRemove.length} stale channel index entries');
    }
  }
}
