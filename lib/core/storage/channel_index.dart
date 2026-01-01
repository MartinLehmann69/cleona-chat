import 'dart:convert';
import 'package:cleona/core/log/clogger.dart';
import 'package:cleona/core/service/service_types.dart';
import 'package:cleona/core/storage/message_store.dart';

/// Local cache + DHT interface for public channel discovery.
///
/// DHT-Key for name uniqueness: SHA-256("channel-name:" + lowercase(name))
/// Local cache stores all known public channel entries for search.
class ChannelIndex {
  final String dataDir;
  final CLogger _log;

  /// The encrypted store of this identity (S366, §21.4.1).
  ///
  /// **Nullable as in `PollManager`**: the GUI client (`ipc_client.dart`)
  /// holds an index only as a cache for what the daemon
  /// sends it, and has no store at all. With `null` nothing is
  /// written and nothing read — the state stays ephemeral.
  final MessageStore? _store;

  /// In-memory cache of known public channels: channelIdHex -> entry.
  final Map<String, ChannelIndexEntry> _entries = {};

  /// Tracks when each entry was last updated locally.
  final Map<String, DateTime> _lastUpdated = {};

  /// Whether [load] has read the store once. Carries the
  /// data-loss latch in [save].
  bool _loaded = false;

  /// The area in the state table — the name of the superseded file
  /// without extension, as with all other collections.
  static const String area = 'channel_index';

  /// S366: the index lives in the encrypted store, no longer in
  /// `channel_index.json.enc`.
  ///
  /// The formerly MANDATORY `fileEnc` parameter was dropped. It came
  /// from S362 and had exactly one task: to force every
  /// construction site to decide visibly under which key
  /// this interest profile lies. That decision is now made one
  /// level higher and more strictly — `CleonaService.store` does not even OPEN
  /// without a seed-derived key (no `db.key` fallback,
  /// `cleona_service.dart`). Leaving a parameter standing that no longer protects anything
  /// would be the more dangerous variant: it would look like
  /// a protection.
  ChannelIndex({
    required this.dataDir,
    this._store,
    CLogger? log,
  })  : // `dataDir` is here already the profileDir of the calling
        // CleonaService (see construction site `cleona_service.dart`).
        _log = log ?? CLogger.get('ChannelIndex', profileDir: dataDir);

  // ── DHT Key derivation ──────────────────────────────────────────

  // DROPPED ON 09.09.2026 (S378): no caller in lib/ or test/.
  // The same class as `dhtKeyForChannel`: DHT key without DHT.
  // The only user was `test/smoke/smoke_public_channels.dart`.

  // DROPPED ON 09.09.2026 (S378): no caller in lib/ or test/.
  // DHT key computation — on this line there is no DHT
  // (`lib/core/dht/` carries zero files). V3 remnant.

  // ── Local cache management ──────────────────────────────────────

  void load() {
    final s = _store;
    if (s == null) {
      _loaded = true;
      return; // Proxy mode (IPC client) — no store, nothing to load
    }
    try {
      for (final e in s.loadArea(area).entries) {
        try {
          // S368: AN ENTRY WITHOUT `u` IS DISCARDED, not set to `now()`.
          // The branch below called it "an old stock from exactly
          // this time; its deadline starts here" — that is a
          // takeover from the time before S366, and old stock does not exist on
          // this line. Setting it to `now()` was moreover
          // exactly the defect that S366 closed, only once instead of
          // on every start: an entry of unknown age would get a
          // fresh 30-day deadline.
          final Object? u = e.value['u'];
          if (u is! int) {
            _log.warn('Channel index: entry ${e.key} carries no '
                'timestamp `u` — discarded (V4.1 takes over no '
                'old stock, S368).');
            continue;
          }
          _entries[e.key] = ChannelIndexEntry.fromJson(e.value);
          // THE TIMESTAMP COMES FROM THE STORE, not from the clock.
          // Until S366 this held `DateTime.now()`, and `save()` did
          // not write it at all (only `version` and `entries`) —
          // after every restart every entry was nominally fresh, and
          // `prune()`, whose only caller runs ONCE at start,
          // could therefore fundamentally discard nothing. The
          // 30-day cap was no cap.
          _lastUpdated[e.key] = DateTime.fromMillisecondsSinceEpoch(u);
        } catch (err) {
          _log.warn('Skipping corrupt channel index entry ${e.key}: $err');
        }
      }
      _loaded = true;
      _log.info('Loaded ${_entries.length} channel index entries');
    } catch (e) {
      _log.warn('Failed to load channel index: $e');
    }
  }

  /// Writes ONE entry — or deletes it if it is no longer there.
  ///
  /// §21.4.1: `channel_index.json` was rewritten COMPLETELY on every single addition,
  /// every new subscriber count and every reconciliation with a neighbour
  /// — in the field profile 50 536 B per change, six
  /// triggers. The index grows with the number of known public
  /// channels; that is exactly the collection `putEntry` is there for.
  void persistEntry(String channelIdHex) {
    final s = _store;
    if (s == null) return;
    try {
      final entry = _entries[channelIdHex];
      if (entry == null) {
        s.removeEntry(area, channelIdHex);
        return;
      }
      s.putEntry(area, channelIdHex, _row(channelIdHex, entry));
    } catch (e) {
      _log.warn('Failed to persist channel index entry $channelIdHex: $e');
    }
  }

  /// The row of an entry: its exchange format plus the LOCAL
  /// timestamp under `u`.
  ///
  /// `u` is deliberately NOT in `ChannelIndexEntry.toJson()`: the quantity
  /// says "when did WE last see this entry" and has no business in the
  /// exchange with a neighbour ([serializeForExchange]). `fromJson` ignores unknown keys,
  /// so the way back needs no special treatment.
  Map<String, dynamic> _row(String channelIdHex, ChannelIndexEntry entry) => {
        ...entry.toJson(),
        'u': (_lastUpdated[channelIdHex] ?? DateTime.now())
            .millisecondsSinceEpoch,
      };

  /// Writes the WHOLE state.
  ///
  /// In normal operation that is the wrong path — there always exactly
  /// one entry changes, and for that there is [persistEntry]. This method
  /// stays for the case that a caller really means the full state.
  void save() {
    final s = _store;
    if (s == null) return;
    // DATA-LOSS LATCH. `replaceArea` deletes the area before it
    // writes: an empty state after a failed load would
    // destroy the stock. The latch asks the STORE — pointed at a
    // file it would never have engaged again after this switch,
    // and the protection would have silently disappeared.
    if (!_loaded && _entries.isEmpty) {
      var present = false;
      try {
        present = s.countArea(area) > 0;
      } catch (e) {
        _log.warn('REFUSED to save channel index — store unreadable: $e');
        return;
      }
      if (present) {
        _log.warn('REFUSED to save empty channel index — load failed but '
            'the store still holds entries. Would cause data loss!');
        return;
      }
    }
    try {
      s.replaceArea(area, {
        for (final e in _entries.entries) e.key: _row(e.key, e.value),
      });
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
    persistEntry(entry.channelIdHex);
  }

  /// Remove a channel from the index (e.g. after deletion/tombstone).
  void remove(String channelIdHex) {
    _entries.remove(channelIdHex);
    _lastUpdated.remove(channelIdHex);
    persistEntry(channelIdHex);
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
          // Only the entries actually taken over are
          // written. A reconciliation that changes two of 400 entries
          // thus costs two rows and not the whole index.
          persistEntry(entry.channelIdHex);
          added++;
        }
      }
      return added;
    } catch (e) {
      _log.warn('Failed to merge channel index: $e');
      return 0;
    }
  }

  /// Prune old entries (not updated for > 30 days).
  ///
  /// S366: THIS CAP ONLY NOW TAKES EFFECT. Until here [load] set the
  /// timestamp of every entry to `DateTime.now()` because `save()` did not
  /// write it at all — and the only caller runs ONCE shortly
  /// after start. `now.difference(...)` was therefore always close to zero there,
  /// `toRemove` always empty, and the index grew without limit (in the field profile
  /// to 50 536 B). Since the timestamp lives in the store under `u`,
  /// it survives the restart and the deadline really runs.
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
      // Discarding was formerly never written either: `prune` only set
      // `_dirty`, and nobody called `save()` after it. A discarded
      // entry was back after the next start.
      persistEntry(key);
    }
    if (toRemove.isNotEmpty) {
      _log.info('Pruned ${toRemove.length} stale channel index entries');
    }
  }
}
