/// The system channels on this device (v4_2 §16.0, §16.7; S407 SK-4).
///
/// ONE per device, beside the identities: the store of objects
/// ([SystemObjectStore], SK-2) and the transport (mycelium
/// `DurableTransport`, SK-1) are device-wide, the report pseudonym is per
/// identity ([SystemChannelService]). The hub keeps:
///
/// * **the own deposits** and their state — saved / deposited (n) /
///   published / failed (§16.7) — one row per object in the device database
///   ([DeviceStore.areaSystemReports]); "published" follows from two
///   distinct holders that acknowledged (`0x91`), never from anything else;
/// * **the edges** of §16.0 — start ([attach]), network change and a new
///   neighbour ([edge], called by the seam), the user opened a channel
///   ([channelOpened]). At each edge a report that rests (no holder, or
///   fewer than two acknowledgements) is deposited again, like a message
///   without a way (D-47). There is no clock: the 14 days of "failed" are
///   checked only when a report would be deposited again (§16.7);
/// * **what a phone learned** at an edge without fetching (§16.7: "marks it
///   as new") — memory only;
/// * **the capable nodes** of the transport across a restart (§16.0; SK-1
///   finding B5), in [DeviceStore.areaDevice].
///
/// A deposit is sent once per edge; the repeats on silence belong to the
/// transport (§11.3a).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/channels/system_channel_api.dart';
import 'package:cleona/core/channels/system_object.dart';
import 'package:cleona/core/channels/system_object_legacy.dart';
import 'package:cleona/core/channels/system_object_stock.dart';
import 'package:cleona/core/channels/system_object_store.dart';
import 'package:cleona/core/util/hex.dart' show bytesToHex, hexToBytes;
import 'package:cleona/core/log/clogger.dart';
import 'package:cleona/core/storage/device_store.dart';
import 'package:cleona/core/storage/encrypted_store.dart';
import 'package:mycelium/durable_stock.dart';

/// One own object on its way out.
class _Own {
  final Uint8List bytes;
  final int channel;
  final int savedMs;
  final Set<String> acked;
  bool holderKnown;
  String? lastReason;
  SystemFailureReason? failure;
  String? detail;

  _Own(this.bytes, this.channel, this.savedMs, this.acked,
      {this.holderKnown = false, this.lastReason, this.failure, this.detail});

  bool get published => acked.length >= SystemReportStatus.kPublishedAt;

  Map<String, dynamic> toJson() => {
        'b': base64Encode(bytes),
        'c': channel,
        't': savedMs,
        'h': acked.toList(),
        'k': holderKnown,
        if (lastReason != null) 'r': lastReason,
        if (failure != null) 'f': failure!.name,
        if (detail != null) 'd': detail,
      };

  static _Own? fromJson(Map<String, dynamic> j) {
    try {
      final f = j['f'] as String?;
      return _Own(base64Decode(j['b'] as String), j['c'] as int,
          j['t'] as int, {...(j['h'] as List).cast<String>()},
          holderKnown: j['k'] as bool? ?? false,
          lastReason: j['r'] as String?,
          failure: f == null
              ? null
              : SystemFailureReason.values.firstWhere((v) => v.name == f),
          detail: j['d'] as String?);
    } catch (_) {
      return null; // a damaged row is skipped
    }
  }
}

class SystemChannelHub {
  /// §16.7: "failed — 14 days without two acknowledgements".
  static const Duration kFailAfter = Duration(days: 14);

  final SystemObjectStore store;
  final EncryptedStore? db;
  final DateTime Function() _now;
  final CLogger _log;

  /// Whether a node (`address:port`) is a device of a contact of any
  /// identity on this device — set by the seam from the mailboxes.
  bool Function(String node) isContact = (_) => false;

  late final SystemObjectStock stock = SystemObjectStock(store,
      isContact: (n) => isContact(n),
      onLearned: _learnedIds,
      onKept: (_) => _keptFromNetwork(),
      readCapable: _readCapable,
      writeCapable: _writeCapable);

  DurableTransport? _transport;
  final StreamController<void> _changes = StreamController<void>.broadcast();
  final Map<int, Map<String, DurableId>> _learned = {};
  final Map<String, _Own> _own = {};
  final Set<String> _depositing = {};

  SystemChannelHub(
      {required this.store,
      this.db,
      DateTime Function()? clock,
      String? profileDir})
      : _now = clock ?? DateTime.now,
        _log = CLogger.get('syschan', profileDir: profileDir) {
    _load();
  }

  static final Expando<SystemChannelHub> _byDb = Expando('system-hub');
  static SystemChannelHub? _memory;

  /// The hub of the device database [db] (one per process and database).
  /// Without a database (no master seed) one in memory.
  static SystemChannelHub forDevice(DeviceStore? db,
      {required bool holds, String? profileDir}) {
    if (db == null) {
      return _memory ??= SystemChannelHub(
          store: SystemObjectStore(holds: holds, profileDir: profileDir));
    }
    return _byDb[db] ??= SystemChannelHub(
        store: SystemObjectStore(store: db, holds: holds, profileDir: profileDir)
          ..load(),
        db: db,
        profileDir: profileDir);
  }

  /// Fires whenever a list, a state or a tally may have changed.
  Stream<void> get changes => _changes.stream;

  void _changed() {
    if (!_changes.isClosed) _changes.add(null);
  }

  bool get attached => _transport != null;

  DurableTransport? get transport => _transport;

  // ── Edges (§16.0) ───────────────────────────────────────────────────

  /// The transport is there — the edge "start".
  void attach(DurableTransport t) {
    if (_transport != null) return;
    _transport = t;
    edge();
  }

  /// Network change or a new neighbour (and start, from [attach]).
  void edge() {
    _transport?.edge();
    _depositResting();
  }

  /// The user opened [channel]: a phone fetches what it lacks.
  void channelOpened(int channel) {
    _transport?.channelOpened(channel);
    _depositResting();
  }

  /// The holders a deposit would ask now (`address:port`).
  List<String> holders() => _transport?.depositHolders() ?? const [];

  // ── Own objects ─────────────────────────────────────────────────────

  /// Writes an own object and deposits it. A refusal of the own store
  /// (the limits of §16.7) writes nothing.
  SystemAdmission submit(Uint8List bytes) {
    final r = store.addOwn(bytes);
    if (!r.kept) return r;
    final o = SystemObject.parse(bytes)!;
    final key = bytesToHex(o.hash);
    if (o.kind == SystemObjectKind.retract) _forget(bytesToHex(o.target!));
    _own.putIfAbsent(
        key, () => _Own(bytes, o.channel, _now().millisecondsSinceEpoch, {}));
    _persist(key);
    _deposit(key);
    _changed();
    return r;
  }

  /// The state of an own object, or `null` when this device did not write
  /// it (it came from another device of the same identity).
  SystemReportStatus? statusOf(String hashHex) {
    final o = _own[hashHex];
    if (o == null) return null;
    return SystemReportStatus(
        acknowledgements: o.acked.length, failure: o.failure, detail: o.detail);
  }

  /// Own objects that are not in the store (refused when re-signed from
  /// 4.2.3, evicted from a phone's read cache): still shown with their
  /// state.
  List<SystemObject> ownOutsideStore(int channel) {
    final out = <SystemObject>[];
    for (final e in _own.entries) {
      if (e.value.channel != channel) continue;
      if (store.isHeld(channel, hexToBytes(e.key))) continue;
      final o = SystemObject.parse(e.value.bytes);
      if (o != null) out.add(o);
    }
    return out;
  }

  void _deposit(String key) {
    final o = _own[key];
    final t = _transport;
    if (o == null || o.published || o.failure != null) return;
    if (_depositing.contains(key)) return;
    final age = _now().millisecondsSinceEpoch - o.savedMs;
    if (age > kFailAfter.inMilliseconds) {
      _fail(key, o);
      return;
    }
    if (t == null) return; // rests until the transport is there
    if (t.depositHolders().isNotEmpty) o.holderKnown = true;
    o.lastReason = null; // this run's end says why, if it ends unpublished
    _depositing.add(key);
    t.deposit(o.channel, o.bytes).listen((e) {
      final h = e.holder;
      if (!e.ended && h != null && o.acked.add(h)) {
        o.holderKnown = true;
        _persist(key);
        _changed();
      }
      if (e.ended) {
        o.lastReason = e.reason;
        _persist(key);
      }
    }, onDone: () {
      _depositing.remove(key);
      _log.info('syschan: deposit of ${key.substring(0, 8)} ended — '
          '${o.acked.length} acknowledgement(s)'
          '${o.lastReason == null ? '' : ', ${o.lastReason}'}');
    });
  }

  void _fail(String key, _Own o) {
    final reason = o.lastReason ?? '';
    if (o.acked.isEmpty && reason.contains('0x94')) {
      o.failure = SystemFailureReason.rejected;
      o.detail = reason;
    } else if (o.holderKnown || o.acked.isNotEmpty) {
      o.failure = SystemFailureReason.notAcknowledged;
    } else {
      o.failure = SystemFailureReason.noHolderKnown;
    }
    _persist(key);
    _changed();
  }

  /// Every own object that rests is deposited again; a published one that
  /// left the store is forgotten.
  void _depositResting() {
    for (final key in List.of(_own.keys)) {
      final o = _own[key]!;
      if (o.published && !store.isHeld(o.channel, hexToBytes(key))) {
        _forget(key);
        continue;
      }
      _deposit(key);
    }
  }

  void _forget(String key) {
    if (_own.remove(key) == null) return;
    db?.removeEntry(DeviceStore.areaSystemReports, key);
  }

  void _persist(String key) {
    final o = _own[key];
    if (o == null) return;
    db?.putEntry(DeviceStore.areaSystemReports, key, o.toJson());
  }

  void _load() {
    final db = this.db;
    if (db == null) return;
    for (final e in db.loadArea(DeviceStore.areaSystemReports).entries) {
      final o = _Own.fromJson(e.value);
      if (o != null) _own[e.key] = o;
    }
  }

  // ── 4.2.3 records (SK-2, `system_object_legacy.dart`) ────────────────

  /// Re-signs the own records the identity wrote under 4.2.3 (they never
  /// left the device) and deposits them; the old rows go. One that the own
  /// limits refuse stays visible as failed, with the reason.
  int resignLegacy(EncryptedStore identityDb,
      {required Uint8List ownUserId, required SystemObjectAuthor author}) {
    final old = readLegacyRecords(identityDb);
    if (old.isEmpty) return 0;
    final out =
        resignLegacyRecords(old, ownUserId: ownUserId, author: author);
    for (final r in out) {
      final a = submit(r.object);
      if (!a.kept) {
        final o = SystemObject.parse(r.object)!;
        final key = bytesToHex(o.hash);
        _own[key] = _Own(r.object, o.channel, _now().millisecondsSinceEpoch,
            {}, failure: SystemFailureReason.rejected, detail: a.reason);
        _persist(key);
      }
    }
    identityDb.replaceArea(kLegacyRecordArea, const {});
    identityDb.replaceArea(kLegacyGoneArea, const {});
    _log.info('syschan: ${out.length} own 4.2.3 record(s) re-signed, '
        '${old.length} old row(s) removed');
    _changed();
    return out.length;
  }

  // ── What a phone learned (§16.7) ────────────────────────────────────

  /// Identifiers learned at an edge and not fetched, by channel.
  List<DurableId> learned(int channel) =>
      (_learned[channel]?.values ?? const <DurableId>[]).toList();

  void _learnedIds(int channel, List<DurableId> ids) {
    final m = _learned[channel] ??= {};
    for (final id in ids) {
      m[bytesToHex(id.hash)] = id;
    }
    _changed();
  }

  void _keptFromNetwork() {
    for (final e in _learned.entries) {
      e.value.removeWhere((h, _) => store.isHeld(e.key, hexToBytes(h)));
    }
    _changed();
  }

  /// The user has seen these objects.
  void seen(int channel, Iterable<Uint8List> hashes) {
    for (final h in hashes) {
      store.markSeen(channel, h);
    }
    _changed();
  }

  // ── Capable nodes (§16.0) ───────────────────────────────────────────

  List<String> _readCapable() {
    final row = db?.entry(DeviceStore.areaDevice, DeviceStore.keySystemCapable);
    return ((row?['v'] as List?) ?? const []).cast<String>();
  }

  void _writeCapable(List<String> nodes) => db?.putEntry(
      DeviceStore.areaDevice, DeviceStore.keySystemCapable, {'v': nodes});

  Future<void> close() => _changes.close();
}
