/// The holdings of the system channels on this device (v4_2 §16.0, §16.7,
/// §21.3.1, D-55). S407 SK-2.
///
/// What it decides, for every object that arrives (fetched, deposited, or
/// built on this device):
///
///   * VALID — the object parses, belongs to its channel, is admissible on
///     this network (a live node rejects one that names a UserID, D-57) and
///     its report-pseudonym signature verifies (§4.4.3);
///   * WITHIN THE LIMITS (§16.7 "Limits, enforced by every receiver") — per
///     pseudonym 3 crash/log reports per hour and 10 per day in the Bug Log,
///     3 Feature Requests per day, and at most 2 % of the channel's budget;
///     one +1 entry per pseudonym and fingerprint; one vote per pseudonym and
///     request, a newer replacing the older;
///   * NOT RETRACTED — a tombstone of the same pseudonym names it.
///
/// A refused object goes into the REJECTED SET (§16.0) and is never fetched
/// again; the set is part of the state root. Identifiers that were heard
/// but never delivered never reach this class — the transport forgets them.
///
/// ── WHAT IT KEEPS, AND WHAT GOES FIRST ────────────────────────────────────
///
/// A desktop holds both channels, 25 MB each. A phone holds none and names
/// none; it keeps at most 5 MB per channel of what it fetched for its user
/// (the read cache, own data — §21.3.1). When a budget is full the oldest
/// object goes first — oldest by its stated creation time — never one the
/// user of this device has seen (own data, §21.1; a phone's read cache is
/// the exception: its cap is hard, so seen objects go last, not never), and
/// never a tombstone before its original: a tombstone takes the place of the
/// original's creation time in the order. An evicted object goes into the
/// rejected set ("limit exceeded", §16.0) — otherwise the next neighbour
/// that names it would make this node fetch it again, and the V3 loop
/// (3.17 GB per node and day) would be back.
///
/// ── WHERE IT LIES ─────────────────────────────────────────────────────────
///
/// In the encrypted device database ([EncryptedStore]; areas
/// `DeviceStore.areaSystemObjects`, `areaSystemRejected`,
/// `areaSystemPlusOnes`), one row per object, written at the moment it
/// changes. No file beside it (§4.5.3, §21.4.2). Without a database
/// ([EncryptedStore] `null`) the holdings live in memory only — the path of
/// the pure checks.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/channels/system_channels.dart';
import 'package:cleona/core/channels/system_object.dart';
import 'package:cleona/core/config/network_channel.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/log/clogger.dart';
import 'package:cleona/core/storage/device_store.dart';
import 'package:cleona/core/storage/encrypted_store.dart';
import 'package:cleona/core/util/hex.dart' show bytesToHex, hexToBytes;
import 'package:mycelium/durable_id.dart';

/// The outcome of an admission. [reason] names why an object was refused.
class SystemAdmission {
  final bool kept;
  final String? reason;
  const SystemAdmission.kept() : kept = true, reason = null;
  const SystemAdmission.rejected(this.reason) : kept = false;

  @override
  String toString() => kept ? 'kept' : 'rejected: $reason';
}

/// A group of crash reports with one fingerprint (§16.7 "Dedup and +1").
class SystemReportGroup {
  /// The oldest valid report.
  final SystemObject head;

  /// Every later report with the same fingerprint — none is discarded.
  final List<SystemObject> variants;

  /// Distinct pseudonyms that added a +1 entry; outlives a retraction.
  final int plusOnes;

  const SystemReportGroup(this.head, this.variants, this.plusOnes);
}

/// The tally of one Feature Request (§16.7): one vote per pseudonym.
class SystemTally {
  final int yes;
  final int no;
  final int dontCare;
  const SystemTally(this.yes, this.no, this.dontCare);
  int get net => yes - no;
}

class _Held {
  final SystemObject object;
  final String hashHex;

  /// When this node accepted it (minutes) — the age it names (§16.0).
  final int acceptedMinutes;

  /// Its place in the eviction order (minutes): its creation time, for a
  /// tombstone the creation time of its original.
  final int evictMinutes;
  bool seen;

  _Held(this.object, this.hashHex, this.acceptedMinutes, this.evictMinutes,
      this.seen);
}

class SystemObjectStore {
  /// Budget per channel of a holder (desktop), §16.7, §21.3.1, D-55.
  static const int kDesktopBudget = SystemChannels.maxChannelStorageBytes;

  /// The read cache per channel of a phone, §16.7, §21.3.1, D-55.
  static const int kPhoneReadCache = 5 * 1024 * 1024;

  /// Share of the CHANNEL's budget (25 MB, on every receiver) one pseudonym
  /// may fill (§16.7: at most 2 %).
  static const int kPseudonymShare = kDesktopBudget * 2 ~/ 100;

  /// An object stated more than this far in the future is refused: a
  /// stated time is the author's, and a far-future one would never age out
  /// of the eviction order.
  static const int kFutureSlackMinutes = 60;

  /// Upper bound of the rejected set per channel — operational, not from
  /// the norm (finding in `mycelium/berichte/S407-SK2.md`). Above it the
  /// oldest rejection is forgotten.
  static const int kRejectedAtMost = 100000;

  static const String _rootLabel = 'cleona-system-root-v1';

  final EncryptedStore? _db;

  /// A holder (always-on desktop) — `false` for a retention-bounded node
  /// (phone), which holds none and names none (§16.0, §5.5).
  final bool holds;

  /// The network this build runs on; decides the beta field (D-57).
  final NetworkChannel network;
  final DateTime Function() _now;
  final CLogger _log;

  final Map<int, Map<String, _Held>> _held = {};
  final Map<int, int> _bytes = {};
  final Map<int, Map<String, int>> _rejected = {};

  /// channel → pseudonym hex → hashes held.
  final Map<int, Map<String, Set<String>>> _byPseudonym = {};

  /// fingerprint hex → report hashes held (Bug Log).
  final Map<String, Set<String>> _byFingerprint = {};

  /// fingerprint hex → pseudonyms that added a +1 (persisted).
  final Map<String, Set<String>> _plusOnes = {};

  /// target hex → pseudonym hex → hash of its vote.
  final Map<String, Map<String, String>> _votes = {};

  /// channel → target hex → hashes of the tombstones naming it. More than
  /// one only while the target is unknown: then nobody can tell which
  /// pseudonym is its author, and none may push another out.
  final Map<int, Map<String, Set<String>>> _tombstones = {};

  /// fingerprint hex → +1 entries held.
  final Map<String, Set<String>> _plusOneObjects = {};

  /// signature hex → hash: a second object with the same signed core (only
  /// the unsigned beta field differs) is a twin, not a variant.
  final Map<String, String> _bySignature = {};

  /// [budgetForTests] replaces the budget of [holds] — only so that a smoke
  /// can fill a channel without 25 MB; the pseudonym share stays 2 % of the
  /// channel's real budget.
  SystemObjectStore({
    EncryptedStore? store,
    required this.holds,
    NetworkChannel? network,
    DateTime Function()? clock,
    String? profileDir,
    int? budgetForTests,
  })  : _db = store,
        network = network ?? activeNetworkChannel,
        _now = clock ?? DateTime.now,
        _budget = budgetForTests ?? (holds ? kDesktopBudget : kPhoneReadCache),
        _log = CLogger.get('syschan', profileDir: profileDir);

  static const List<int> channels = [kChannelBugLog, kChannelFeatureRequests];

  final int _budget;

  /// Bytes per channel: 25 MB on a holder, 5 MB read cache on a phone.
  int get budget => _budget;

  int get _nowMinutes => minutesOf(_now());

  static String _key(int channel, String hashHex) => '$channel:$hashHex';

  // ── Queries ─────────────────────────────────────────────────────────

  bool isHeld(int channel, Uint8List hash) =>
      _held[channel]?.containsKey(bytesToHex(hash)) ?? false;

  bool isRejected(int channel, Uint8List hash) =>
      _rejected[channel]?.containsKey(bytesToHex(hash)) ?? false;

  SystemObject? objectOf(int channel, Uint8List hash) =>
      _held[channel]?[bytesToHex(hash)]?.object;

  /// Bytes held in [channel].
  int bytesIn(int channel) => _bytes[channel] ?? 0;

  int heldCount(int channel) => _held[channel]?.length ?? 0;

  int rejectedCount(int channel) => _rejected[channel]?.length ?? 0;

  /// Identifiers of [channel], newest accepted first, with the age this
  /// node states; [sinceHours] keeps only those at most so old.
  List<DurableId> identifiers(int channel, {int? sinceHours}) {
    final now = _nowMinutes;
    final list = (_held[channel]?.values ?? const <_Held>[]).toList()
      ..sort((a, b) {
        final c = b.acceptedMinutes.compareTo(a.acceptedMinutes);
        return c != 0 ? c : a.hashHex.compareTo(b.hashHex);
      });
    final out = <DurableId>[];
    for (final h in list) {
      final age = ((now - h.acceptedMinutes) ~/ 60).clamp(0, 0xFFFF);
      if (sinceHours != null && age > sinceHours) continue;
      out.add(h.object.id(ageHours: age));
    }
    return out;
  }

  /// The state root of [channel] (§16.0): SHA-256 over a label, the channel
  /// and the sorted 16 B hashes of every identifier held AND rejected. The
  /// age is not part of it — it changes every hour on every node.
  Uint8List stateRoot(int channel) {
    final all = <String>{
      ...?_held[channel]?.keys,
      ...?_rejected[channel]?.keys,
    }.toList()
      ..sort();
    final b = BytesBuilder(copy: false)
      ..add(utf8.encode(_rootLabel))
      ..addByte(channel);
    for (final h in all) {
      b.add(hexToBytes(h));
    }
    return SodiumFFI().sha256(b.toBytes());
  }

  /// All reports of [channel], oldest first.
  List<SystemObject> reports(int channel) => _sortedObjects(
      (_held[channel]?.values ?? const <_Held>[])
          .where((h) => h.object.kind == SystemObjectKind.report));

  /// The group of crash fingerprint [fingerprint], or `null`.
  SystemReportGroup? group(Uint8List fingerprint) {
    final fp = bytesToHex(fingerprint);
    final hashes = _byFingerprint[fp];
    if (hashes == null || hashes.isEmpty) return null;
    final reps = _sortedObjects([
      for (final h in hashes) _held[kChannelBugLog]![h]!,
    ]);
    return SystemReportGroup(
        reps.first, reps.sublist(1), _plusOnes[fp]?.length ?? 0);
  }

  /// The head of the group for [fingerprint] (0x97 → 0x98), or `null`.
  Uint8List? headFor(int channel, Uint8List fingerprint) {
    if (channel != kChannelBugLog) return null;
    return group(fingerprint)?.head.bytes;
  }

  int plusOneCount(Uint8List fingerprint) =>
      _plusOnes[bytesToHex(fingerprint)]?.length ?? 0;

  /// The tally of the Feature Request [target] (hash part of its id).
  SystemTally tally(Uint8List target) {
    var yes = 0, no = 0, dontCare = 0;
    for (final h in (_votes[bytesToHex(target)] ?? const {}).values) {
      switch (_held[kChannelFeatureRequests]![h]!.object.option) {
        case SystemVote.yes:
          yes++;
        case SystemVote.no:
          no++;
        default:
          dontCare++;
      }
    }
    return SystemTally(yes, no, dontCare);
  }

  /// The current vote of [pseudonym] on [target], or `null`.
  SystemObject? voteOf(Uint8List target, Uint8List pseudonym) {
    final h = _votes[bytesToHex(target)]?[bytesToHex(pseudonym)];
    return h == null ? null : _held[kChannelFeatureRequests]![h]!.object;
  }

  /// The time a NEW vote of [pseudonym] on [target] must state so that it
  /// replaces the current one: now, or one minute after the current vote.
  DateTime nextVoteTime(Uint8List target, Uint8List pseudonym) {
    final now = _now();
    final cur = voteOf(target, pseudonym);
    if (cur == null || cur.createdMinutes < minutesOf(now)) return now;
    return DateTime.fromMillisecondsSinceEpoch(
        (cur.createdMinutes + 1) * Duration.millisecondsPerMinute,
        isUtc: true);
  }

  List<SystemObject> _sortedObjects(Iterable<_Held> hs) {
    final l = hs.toList()
      ..sort((a, b) {
        final c = a.object.createdMinutes.compareTo(b.object.createdMinutes);
        return c != 0 ? c : a.hashHex.compareTo(b.hashHex);
      });
    return [for (final h in l) h.object];
  }

  // ── Seen ────────────────────────────────────────────────────────────

  /// The user of this device has seen the object: it is own data from now
  /// on and never evicted (§16.7, §21.1).
  void markSeen(int channel, Uint8List hash) {
    final h = _held[channel]?[bytesToHex(hash)];
    if (h == null || h.seen) return;
    h.seen = true;
    _persistHeld(channel, h);
  }

  bool isSeen(int channel, Uint8List hash) =>
      _held[channel]?[bytesToHex(hash)]?.seen ?? false;

  // ── Admission ───────────────────────────────────────────────────────

  /// An object built on this device: admitted under the same rules as any
  /// other (the author's own limits hold for it too) and marked seen.
  SystemAdmission addOwn(Uint8List bytes) {
    final o = SystemObject.parse(bytes);
    if (o == null) return const SystemAdmission.rejected('malformed');
    final r = offer(o.channel, bytes);
    if (r.kept) markSeen(o.channel, o.hash);
    return r;
  }

  /// The checks of [offer] for an own report or +1 BEFORE it is written —
  /// the preview refuses what the own limits forbid (§16.7). `null`:
  /// admissible. Nothing is written: for a fresh report or +1 the checks
  /// have no side effect (no tombstone can name an object not yet built).
  String? ownCheck(Uint8List bytes) {
    final o = SystemObject.parse(bytes);
    if (o == null) return 'malformed';
    if (o.kind != SystemObjectKind.report &&
        o.kind != SystemObjectKind.plusOne) {
      throw ArgumentError('ownCheck: reports and +1 entries only');
    }
    final hashHex = bytesToHex(objectHash(bytes));
    if (_held[o.channel]?.containsKey(hashHex) ?? false) return null;
    if (_rejected[o.channel]?.containsKey(hashHex) ?? false) {
      return 'rejected before';
    }
    return _check(o.channel, bytes, hashHex);
  }

  /// Whether [pseudonym] has a +1 entry for [fingerprint].
  bool hasPlusOne(Uint8List fingerprint, Uint8List pseudonym) =>
      _plusOnes[bytesToHex(fingerprint)]?.contains(bytesToHex(pseudonym)) ??
      false;

  /// The channel that holds the object with hash part [hash], or `null`.
  int? channelOf(Uint8List hash) {
    final h = bytesToHex(hash);
    for (final c in channels) {
      if (_held[c]?.containsKey(h) ?? false) return c;
    }
    return null;
  }

  /// A fetched or deposited object for [channel] (§16.0): kept, or rejected
  /// into the rejected set.
  SystemAdmission offer(int channel, Uint8List bytes) {
    if (!channels.contains(channel)) {
      return const SystemAdmission.rejected('unknown channel');
    }
    final hashHex = bytesToHex(objectHash(bytes));
    if (_held[channel]?.containsKey(hashHex) ?? false) {
      return const SystemAdmission.kept();
    }
    if (_rejected[channel]?.containsKey(hashHex) ?? false) {
      return const SystemAdmission.rejected('rejected before');
    }
    final reason = _check(channel, bytes, hashHex);
    if (reason != null) return _reject(channel, hashHex, reason);
    final o = SystemObject.parse(bytes)!;
    _apply(channel, o, hashHex);
    if (!(_held[channel]?.containsKey(hashHex) ?? false)) {
      return const SystemAdmission.rejected('budget full');
    }
    return const SystemAdmission.kept();
  }

  /// Every check; `null` = admissible. Side effects only where a check
  /// settles an earlier object (a bogus tombstone, a replaced vote).
  String? _check(int channel, Uint8List bytes, String hashHex) {
    final o = SystemObject.parse(bytes);
    if (o == null) return 'malformed';
    if (o.channel != channel) return 'wrong channel';
    if (!o.fitsChannel) return 'kind does not fit the channel';
    if (!o.admissibleOn(network)) return 'names a UserID on live';
    if (o.createdMinutes > _nowMinutes + kFutureSlackMinutes) {
      return 'stated in the future';
    }
    if (bytes.length > kPseudonymShare) return 'larger than the share';
    if (!o.verifies) return 'signature';
    if (_bySignature.containsKey(bytesToHex(o.signature))) {
      return 'twin of a held object';
    }
    final pk = bytesToHex(o.pseudonym);

    // Retracted? A tombstone of the same pseudonym wins; one of another
    // pseudonym was bogus and gives way.
    final tombs = [
      for (final t in _tombstones[channel]?[hashHex] ?? const <String>{})
        _held[channel]![t]!
    ];
    if (tombs.any((t) => bytesToHex(t.object.pseudonym) == pk)) {
      return 'retracted';
    }
    for (final t in tombs) {
      _evict(channel, t, 'tombstone of another pseudonym');
    }

    // Per pseudonym: 2 % of the channel's budget.
    final mine = _byPseudonym[channel]?[pk] ?? const <String>{};
    var used = 0;
    for (final h in mine) {
      used += _held[channel]![h]!.object.bytes.length;
    }
    if (used + bytes.length > kPseudonymShare) return 'pseudonym share full';

    switch (o.kind) {
      case SystemObjectKind.report:
        final hour = o.createdMinutes ~/ 60;
        final day = o.createdMinutes ~/ (24 * 60);
        var inHour = 0, inDay = 0;
        for (final h in mine) {
          final x = _held[channel]![h]!.object;
          if (x.kind != SystemObjectKind.report) continue;
          if (x.createdMinutes ~/ 60 == hour) inHour++;
          if (x.createdMinutes ~/ (24 * 60) == day) inDay++;
        }
        if (channel == kChannelBugLog) {
          if (inHour >= SystemChannels.maxReportsPerHour) return 'rate per hour';
          if (inDay >= SystemChannels.maxReportsPerDay) return 'rate per day';
        } else if (inDay >= SystemChannels.maxFeaturePostsPerDay) {
          return 'rate per day';
        }
      case SystemObjectKind.plusOne:
        if (_plusOnes[bytesToHex(o.fingerprint!)]?.contains(pk) ?? false) {
          return 'one +1 per pseudonym';
        }
      case SystemObjectKind.vote:
        final cur = _votes[bytesToHex(o.target!)]?[pk];
        if (cur != null) {
          final c = _held[channel]![cur]!;
          if (!_newer(o, hashHex, c.object, c.hashHex)) return 'older vote';
          _evict(channel, c, 'replaced by a newer vote');
        }
      case SystemObjectKind.retract:
        final target = bytesToHex(o.target!);
        for (final t in _tombstones[channel]?[target] ?? const <String>{}) {
          if (bytesToHex(_held[channel]![t]!.object.pseudonym) == pk) {
            return 'retracted already';
          }
        }
        final t = _held[channel]?[target];
        if (t != null) {
          if (bytesToHex(t.object.pseudonym) != pk) {
            return 'retraction by another pseudonym';
          }
          if (t.object.kind == SystemObjectKind.retract) {
            return 'retraction of a retraction';
          }
        }
    }
    return null;
  }

  static bool _newer(SystemObject a, String ah, SystemObject b, String bh) {
    final c = a.createdMinutes.compareTo(b.createdMinutes);
    return c != 0 ? c > 0 : ah.compareTo(bh) > 0;
  }

  void _apply(int channel, SystemObject o, String hashHex) {
    var evictAt = o.createdMinutes;
    if (o.kind == SystemObjectKind.retract) {
      final target = bytesToHex(o.target!);
      final t = _held[channel]?[target];
      if (t != null) {
        evictAt = t.evictMinutes;
        _evict(channel, t, 'retracted');
      } else if (_rejected[channel]?.containsKey(target) ?? false) {
        // The original went before (evicted); the tombstone keeps its place.
        evictAt = o.createdMinutes;
      }
    }
    final h = _Held(o, hashHex, _nowMinutes, evictAt, false);
    _index(channel, h);
    if (o.kind == SystemObjectKind.plusOne) {
      final fp = bytesToHex(o.fingerprint!);
      (_plusOnes[fp] ??= {}).add(bytesToHex(o.pseudonym));
      _persistPlusOnes(fp);
    }
    _persistHeld(channel, h);
    _fitBudget(channel);
  }

  void _index(int channel, _Held h) {
    final o = h.object;
    (_held[channel] ??= {})[h.hashHex] = h;
    _bytes[channel] = (_bytes[channel] ?? 0) + o.bytes.length;
    final pk = bytesToHex(o.pseudonym);
    ((_byPseudonym[channel] ??= {})[pk] ??= {}).add(h.hashHex);
    _bySignature[bytesToHex(o.signature)] = h.hashHex;
    switch (o.kind) {
      case SystemObjectKind.report:
        if (o.fingerprint != null) {
          (_byFingerprint[bytesToHex(o.fingerprint!)] ??= {}).add(h.hashHex);
        }
      case SystemObjectKind.plusOne:
        (_plusOneObjects[bytesToHex(o.fingerprint!)] ??= {}).add(h.hashHex);
      case SystemObjectKind.vote:
        (_votes[bytesToHex(o.target!)] ??= {})[pk] = h.hashHex;
      case SystemObjectKind.retract:
        ((_tombstones[channel] ??= {})[bytesToHex(o.target!)] ??= {})
            .add(h.hashHex);
    }
  }

  void _unindex(int channel, _Held h) {
    final o = h.object;
    _held[channel]?.remove(h.hashHex);
    _bytes[channel] = (_bytes[channel] ?? 0) - o.bytes.length;
    final pk = bytesToHex(o.pseudonym);
    _byPseudonym[channel]?[pk]?.remove(h.hashHex);
    if (_byPseudonym[channel]?[pk]?.isEmpty ?? false) {
      _byPseudonym[channel]!.remove(pk);
    }
    _bySignature.remove(bytesToHex(o.signature));
    switch (o.kind) {
      case SystemObjectKind.report:
        if (o.fingerprint != null) {
          final fp = bytesToHex(o.fingerprint!);
          _byFingerprint[fp]?.remove(h.hashHex);
          if (_byFingerprint[fp]?.isEmpty ?? false) _byFingerprint.remove(fp);
        }
      case SystemObjectKind.plusOne:
        final fp = bytesToHex(o.fingerprint!);
        _plusOneObjects[fp]?.remove(h.hashHex);
        if (_plusOneObjects[fp]?.isEmpty ?? false) _plusOneObjects.remove(fp);
      case SystemObjectKind.vote:
        final t = bytesToHex(o.target!);
        if (_votes[t]?[pk] == h.hashHex) _votes[t]!.remove(pk);
        if (_votes[t]?.isEmpty ?? false) _votes.remove(t);
      case SystemObjectKind.retract:
        final t = bytesToHex(o.target!);
        _tombstones[channel]?[t]?.remove(h.hashHex);
        if (_tombstones[channel]?[t]?.isEmpty ?? false) {
          _tombstones[channel]!.remove(t);
        }
    }
  }

  /// Drops a held object into the rejected set.
  void _evict(int channel, _Held h, String reason) {
    _unindex(channel, h);
    _forgetHeld(channel, h.hashHex);
    _reject(channel, h.hashHex, reason);
    _dropPlusOnesIfOrphaned(h.object);
  }

  /// The +1 count outlives a retraction, but not the fingerprint: when no
  /// held object names it any more, its row goes.
  void _dropPlusOnesIfOrphaned(SystemObject o) {
    final fp = o.fingerprint;
    if (fp == null || o.channel != kChannelBugLog) return;
    final fpHex = bytesToHex(fp);
    if (_byFingerprint.containsKey(fpHex)) return;
    if (_plusOneObjects.containsKey(fpHex)) return;
    if (_plusOnes.remove(fpHex) != null) {
      try {
        _db?.removeEntry(DeviceStore.areaSystemPlusOnes, fpHex);
      } catch (e) {
        _log.warn('syschan: remove +1 row failed: $e');
      }
    }
  }

  SystemAdmission _reject(int channel, String hashHex, String reason) {
    final set = _rejected[channel] ??= {};
    set[hashHex] = _nowMinutes;
    try {
      _db?.putEntry(DeviceStore.areaSystemRejected, _key(channel, hashHex),
          {'t': set[hashHex]});
    } catch (e) {
      _log.warn('syschan: persist rejection failed: $e');
    }
    if (set.length > kRejectedAtMost) {
      final oldest = set.entries.reduce((a, b) => a.value <= b.value ? a : b);
      set.remove(oldest.key);
      try {
        _db?.removeEntry(
            DeviceStore.areaSystemRejected, _key(channel, oldest.key));
      } catch (_) {}
    }
    _log.debug('syschan: ${hashHex.substring(0, 8)} in $channel rejected: '
        '$reason');
    return SystemAdmission.rejected(reason);
  }

  /// Evicts the oldest objects until [channel] fits its budget (§16.7):
  /// never a seen one on a holder; on a phone seen ones go last.
  void _fitBudget(int channel) {
    if (bytesIn(channel) <= budget) return;
    int order(_Held a, _Held b) {
      final c = a.evictMinutes.compareTo(b.evictMinutes);
      return c != 0 ? c : a.hashHex.compareTo(b.hashHex);
    }

    final all = _held[channel]!.values.toList();
    final unseen = all.where((h) => !h.seen).toList()..sort(order);
    final queue = [
      ...unseen,
      if (!holds) ...(all.where((h) => h.seen).toList()..sort(order)),
    ];
    var n = 0;
    for (final h in queue) {
      if (bytesIn(channel) <= budget) break;
      _evict(channel, h, 'budget');
      n++;
    }
    if (n > 0) {
      _log.info('syschan: $n object(s) evicted from channel $channel '
          '(budget ${budget ~/ (1024 * 1024)} MB)');
    }
  }

  // ── Persistence ─────────────────────────────────────────────────────

  void _persistHeld(int channel, _Held h) {
    try {
      _db?.putEntry(DeviceStore.areaSystemObjects, _key(channel, h.hashHex), {
        'b': base64Encode(h.object.bytes),
        'a': h.acceptedMinutes,
        's': h.seen,
        'o': h.evictMinutes,
      });
    } catch (e) {
      _log.warn('syschan: persist object failed: $e');
    }
  }

  void _forgetHeld(int channel, String hashHex) {
    try {
      _db?.removeEntry(DeviceStore.areaSystemObjects, _key(channel, hashHex));
    } catch (e) {
      _log.warn('syschan: remove object failed: $e');
    }
  }

  void _persistPlusOnes(String fpHex) {
    try {
      _db?.putEntry(DeviceStore.areaSystemPlusOnes, fpHex,
          {'p': _plusOnes[fpHex]!.toList()});
    } catch (e) {
      _log.warn('syschan: persist +1 row failed: $e');
    }
  }

  /// Loads the holdings from the database. The hash is recomputed from the
  /// bytes, never taken from the key: a row whose key does not match its
  /// content must not come back under a false name.
  void load() {
    final db = _db;
    if (db == null) return;
    try {
      for (final e in db.loadArea(DeviceStore.areaSystemRejected).entries) {
        final p = _splitKey(e.key);
        if (p == null) continue;
        (_rejected[p.$1] ??= {})[p.$2] = (e.value['t'] as num?)?.toInt() ?? 0;
      }
      for (final e in db.loadArea(DeviceStore.areaSystemPlusOnes).entries) {
        final list = e.value['p'];
        if (list is! List) continue;
        _plusOnes[e.key] = {for (final x in list) '$x'};
      }
      for (final e in db.loadArea(DeviceStore.areaSystemObjects).entries) {
        final p = _splitKey(e.key);
        if (p == null) continue;
        try {
          final bytes = base64Decode(e.value['b'] as String);
          final o = SystemObject.parse(bytes);
          if (o == null || o.channel != p.$1) continue;
          final hashHex = bytesToHex(objectHash(bytes));
          _index(
              p.$1,
              _Held(
                  o,
                  hashHex,
                  (e.value['a'] as num?)?.toInt() ?? 0,
                  (e.value['o'] as num?)?.toInt() ?? o.createdMinutes,
                  e.value['s'] == true));
        } catch (_) {/* skip a damaged row */}
      }
    } catch (e) {
      _log.warn('syschan: load failed: $e');
    }
  }

  static (int, String)? _splitKey(String key) {
    final i = key.indexOf(':');
    if (i <= 0) return null;
    final ch = int.tryParse(key.substring(0, i));
    if (ch == null || !channels.contains(ch)) return null;
    return (ch, key.substring(i + 1));
  }
}
