// D-99 (S413) — every own device carries every identity of the user
// (V4.2 §4.5.1, §13.3.4, §14.4, §14.7 Type 23 IDENTITY_SET, §14.9.3).
//
// ── WHAT TRAVELS ─────────────────────────────────────────────────────────
//
// The identity list of this device: per identity its HD index, display
// name, creation time, `active` flag (§13.3.2), the DeviceID this device
// carries in it and whether it holds random state (contacts, rotated keys,
// invitations). A deleted index is listed with `active = false`. Or one
// piece (at most 32 KB) of one identity's handover (§14.6.2).
//
// ── WHEN ─────────────────────────────────────────────────────────────────
//
// Only at an event, never on a timer (§5.4, working rule 5): when an
// identity is created (its attachment changes the list) or deleted
// ([identitySetDeleting]), once at the first start of this version (the
// device database holds no list sent yet), and in answer to a list that
// differs from the own one. Every answer removes a difference, so the
// exchange ends.
//
// ── ON WHICH LINE ────────────────────────────────────────────────────────
//
// The own line of an identity both devices carry (§14.7): per other own
// device the first identity of this host whose device set names it, to the
// DeviceID it has there. A device is recognised across identities by its
// DeviceID (one per device, D-104) and by the node identifier of the device
// that its list names (`node`, §4.1) — not by its device keys or the
// identifier of a device set, which differ per identity (D-106).
//
// ── WHAT THE RECEIVER DOES ([identitySetPlan]) ───────────────────────────
//
//   * an identity it does not carry and has not deleted → created from the
//     seed (§4.5.1), started by the host (`onIdentityFound`), its device set
//     filled with every own device whose list names it; its first bundle
//     waits for the cadence counted from the creation time the list names
//     (§13.3.4);
//   * `active = false` → deleted as Type 17 does;
//   * an identity both carry whose set lacks the sender → the sender joins;
//     its contacts (Type 0), groups (Type 6) and channels (Type 22) go to the
//     sender — unless the sender carries a fresh copy without random state
//     while this device's holds some: then the handover goes instead, in
//     pieces, and the sender takes it over as at enrolment;
//   * a differing list is answered with the own one.
//
// An earlier 4.2 version skips the type (`twinSyncTypeIsUnknown`), never
// sends a list and is therefore never entered into a new identity's set.

part of 'cleona_service.dart';

/// The largest handover piece in raw bytes: base64 and the JSON frame keep
/// the payload of one piece within 32 KB (§14.7 Type 23).
const int kIdentitySetPieceRaw = 24 * 1024 - 256;

/// One entry of an identity list (§14.7 Type 23).
class IdentitySetEntry {
  final int index;
  final String name;
  final int createdAtMs;
  final bool active;

  /// The DeviceID the sending device carries in this identity (hex), `''`
  /// when it does not run it.
  final String deviceIdHex;

  /// The sending device's copy holds random state: contacts, groups,
  /// channels, rotated keys or invitations (§14.6.2).
  final bool history;

  const IdentitySetEntry({
    required this.index,
    this.name = '',
    this.createdAtMs = 0,
    required this.active,
    this.deviceIdHex = '',
    this.history = false,
  });

  Map<String, dynamic> toJson() => {
        'i': index,
        if (active) 'n': name,
        if (active) 'c': createdAtMs,
        'a': active,
        if (deviceIdHex.isNotEmpty) 'u': deviceIdHex,
        if (history) 'h': true,
      };

  static IdentitySetEntry? fromJson(Object? j) {
    if (j is! Map) return null;
    final i = j['i'];
    if (i is! int || i < 0) return null;
    return IdentitySetEntry(
      index: i,
      name: j['n'] as String? ?? '',
      createdAtMs: j['c'] as int? ?? 0,
      active: j['a'] == true,
      deviceIdHex: j['u'] as String? ?? '',
      history: j['h'] == true,
    );
  }
}

/// What names the device of record [r] across identities (D-106): this
/// device, its DeviceID (one per device, D-104) and the node identifier of
/// the device (§4.1, Type 23 `node`). Two records sharing one of them are
/// one device. The device keys and the identifier of the device set differ
/// per identity and name nothing across identities.
Set<String> deviceRecordKeys(DeviceRecord r) => {
      if (r.isThisDevice) 'this',
      if (r.nodeOfDeviceHex != null) 'n:${r.nodeOfDeviceHex}',
      'u:${r.deviceId}',
    };

/// Whether records [a] and [b] (of any two identities of this host) name
/// the same other own device (D-106).
bool deviceRecordsSame(DeviceRecord a, DeviceRecord b) =>
    !a.isThisDevice &&
    !b.isThisDevice &&
    (a.deviceId == b.deviceId ||
        (a.nodeOfDeviceHex != null && a.nodeOfDeviceHex == b.nodeOfDeviceHex));

/// The payload of a list (§14.7 Type 23): [nodeIdHex] is the sending
/// device's node id, the one name of the device across its identities.
Uint8List identitySetListBody(
        {required String nodeIdHex, required List<IdentitySetEntry> entries}) =>
    Uint8List.fromList(utf8.encode(jsonEncode({
      'v': 1,
      'node': nodeIdHex,
      'ids': [for (final e in entries) e.toJson()],
    })));

/// The entries of a list payload; `null` when it is none (a piece, or not
/// readable).
List<IdentitySetEntry>? identitySetEntriesOf(Map<String, dynamic> j) {
  final ids = j['ids'];
  if (ids is! List) return null;
  return [for (final x in ids) ?IdentitySetEntry.fromJson(x)];
}

/// What the list changes when it is sent again: the indices, their flags and
/// the DeviceIDs. A name is no part of it (Type 7 carries a change).
String identitySetSignature(List<IdentitySetEntry> entries) {
  final sorted = List.of(entries)..sort((a, b) => a.index.compareTo(b.index));
  return sorted
      .map((e) => '${e.index}:${e.active ? 1 : 0}:${e.deviceIdHex}')
      .join(',');
}

/// Whether two lists name the same living and the same deleted indices.
bool identitySetSame(List<IdentitySetEntry> a, List<IdentitySetEntry> b) {
  Set<int> live(List<IdentitySetEntry> l) =>
      {for (final e in l) if (e.active) e.index};
  Set<int> gone(List<IdentitySetEntry> l) =>
      {for (final e in l) if (!e.active) e.index};
  final la = live(a), lb = live(b), ga = gone(a), gb = gone(b);
  return la.length == lb.length &&
      la.containsAll(lb) &&
      ga.length == gb.length &&
      ga.containsAll(gb);
}

/// What one identity of the receiving device brings to [identitySetPlan].
typedef IdentitySetCarried = ({bool history, bool senderInSet});

/// What the receiver of a list does (§14.7 Type 23), as a pure rule.
typedef IdentitySetPlan = ({
  List<int> create,
  List<int> delete,
  List<int> noteDeleted,
  List<int> join,
  List<int> merge,
  List<int> handOver,
  bool answer,
});

/// The rule of §14.7 Type 23 for a [received] list against the identities
/// this device [carried] (by index) and the indices it [deleted].
///
/// `handOver` ⊂ `join`: the sender carries a fresh copy (no random state)
/// of an identity whose copy here holds some — it gets the handover. The
/// rest of `join` is `merge`: one identity created twice, contacts, groups
/// and channels go across. `answer`: the lists differ, or the sender was
/// missing from a set here (then it likely misses this device too).
IdentitySetPlan identitySetPlan({
  required List<IdentitySetEntry> received,
  required Map<int, IdentitySetCarried> carried,
  required Set<int> deleted,
  required List<IdentitySetEntry> own,
}) {
  final create = <int>[], delete = <int>[], noteDeleted = <int>[];
  final join = <int>[], merge = <int>[], handOver = <int>[];
  for (final e in received) {
    final here = carried[e.index];
    if (!e.active) {
      if (here != null) {
        delete.add(e.index);
      } else if (!deleted.contains(e.index)) {
        noteDeleted.add(e.index);
      }
      continue;
    }
    if (deleted.contains(e.index)) continue; // the answer names it deleted
    if (here == null) {
      create.add(e.index);
      continue;
    }
    if (here.senderInSet || e.deviceIdHex.isEmpty) continue;
    join.add(e.index);
    if (here.history && !e.history) {
      handOver.add(e.index);
    } else {
      merge.add(e.index);
    }
  }
  return (
    create: create,
    delete: delete,
    noteDeleted: noteDeleted,
    join: join,
    merge: merge,
    handOver: handOver,
    answer: !identitySetSame(own, received) || join.isNotEmpty,
  );
}

/// Per host: the list signature sent in this run and to which devices (by
/// device node id), and the handover pieces being put together.
class _IdentitySetRun {
  String? signature;
  final Set<String> sentTo = {};
  final Map<String, Map<int, Uint8List>> pieces = {};
  final Set<String> handedOver = {};
}

final Expando<_IdentitySetRun> _identitySetRuns = Expando('identity-set');

/// §13.3.4: the creation time a list named for an identity this device
/// created from it — its first bundle is due from there (`baseDir#index`).
final Map<String, int> _identitySetFirstBundleAt = {};

/// The creation time to count the first bundle of the identity at [index]
/// under [baseDir] from, taken once (`_recoveryBundleAttach`).
int? identitySetFirstBundleTake(String baseDir, int index) =>
    _identitySetFirstBundleAt.remove('$baseDir#$index');

extension CleonaServiceIdentitySet on CleonaService {
  _IdentitySetRun? get _identitySetRun {
    final p = myceliumMailbox;
    if (p == null) return null;
    return _identitySetRuns[p.host] ??= _IdentitySetRun();
  }

  List<CleonaService> get _identitySetServices {
    final p = myceliumMailbox;
    final all = p == null ? [this] : servicesOnHost(p.host, this);
    return all
      ..sort((a, b) =>
          (a.identity.hdIndex ?? 1 << 30).compareTo(b.identity.hdIndex ?? 1 << 30));
  }

  /// The one name of [r]'s device across the identities (§4.1, D-106): the
  /// node identifier of the device once its list named it, its DeviceID
  /// before.
  static String _deviceOf(DeviceRecord r) => r.nodeOfDeviceHex ?? r.deviceId;

  String? get _identitySetOwnDeviceId {
    for (final d in _devices.values) {
      if (d.isThisDevice) return d.deviceId;
    }
    return null;
  }

  /// Random state of this identity that the seed does not give (§14.6.2).
  /// A KEM rotation counts by [IdentityContext.keyRotatedAt], not by the
  /// predecessor: the predecessor goes after 7 days (§4.5.4), the random
  /// current generation stays.
  bool get _identitySetHistory =>
      _contacts.isNotEmpty ||
      _deletedContacts.isNotEmpty ||
      _groups.isNotEmpty ||
      _channels.isNotEmpty ||
      identity.hasRotated ||
      identity.keyRotatedAt != null ||
      inviteLedger.records.isNotEmpty;

  /// The identity list of this device. [deleting]: an index being deleted
  /// right now, listed as deleted already.
  List<IdentitySetEntry> identitySetOwn({int? deleting}) {
    final mgr = _identityMgr;
    final deleted = {...mgr.deletedHdIndices(), ?deleting};
    final running = {
      for (final s in _identitySetServices)
        if (s.identity.hdIndex != null) s.identity.hdIndex!: s
    };
    final entries = <IdentitySetEntry>[];
    for (final id in mgr.loadIdentities()) {
      final i = id.hdIndex;
      if (i == null || deleted.contains(i)) continue;
      final s = running[i];
      entries.add(IdentitySetEntry(
        index: i,
        name: id.displayName,
        createdAtMs: id.createdAt.millisecondsSinceEpoch,
        active: true,
        deviceIdHex: s?._identitySetOwnDeviceId ?? '',
        history: s?._identitySetHistory ?? false,
      ));
    }
    for (final i in deleted) {
      entries.add(IdentitySetEntry(index: i, active: false));
    }
    entries.sort((a, b) => a.index.compareTo(b.index));
    return entries;
  }

  /// Sends the identity list to the other own devices — every one, or the
  /// devices named in [only] (by device node id). A device reached in this
  /// run with the same list is not sent it again. [not]: a service that is
  /// being deleted and carries the list no more.
  int _identitySetSend(
      {Set<String>? only, int? deleting, CleonaService? not}) {
    final run = _identitySetRun;
    if (run == null || identity.masterSeed == null) return 0;
    final List<IdentitySetEntry> entries;
    try {
      entries = identitySetOwn(deleting: deleting);
    } on Object catch (e) {
      _log.warn('Identity list (§14.7 Type 23): not built — $e');
      return 0;
    }
    final signature = identitySetSignature(entries);
    if (run.signature != signature) {
      run.signature = signature;
      run.sentTo.clear();
      try {
        _identityMgr.identitySetSentPut(signature);
      } on Object catch (e) {
        _log.warn('Identity list (§14.7 Type 23): not noted as sent — $e');
      }
    }
    // §4.1 (D-106): the node identifier of the device, not the identifier
    // of one identity's device set.
    final body = identitySetListBody(
        nodeIdHex: identity.deviceNodeOfDeviceHex, entries: entries);
    var sent = 0;
    for (final s in _identitySetServices) {
      if (identical(s, not) || s.myceliumMailbox == null) continue;
      for (final r in s._devices.values) {
        if (r.isThisDevice || r.deviceId.length != 32) continue;
        final d = _deviceOf(r);
        if (only != null && !only.contains(d)) continue;
        if (!run.sentTo.add(d)) continue;
        s._sendTwinSync(proto.TwinSyncType.IDENTITY_SET, body,
            targetDeviceId: hexToBytes(r.deviceId));
        sent++;
      }
    }
    if (sent > 0) {
      _log.info('Identity list (§14.7 Type 23): ${entries.length} '
          'entr${entries.length == 1 ? "y" : "ies"}, ${body.length} B, to '
          '$sent own device(s)');
    }
    return sent;
  }

  /// At the attachment of this identity (`myceliumAttach`), after the end of
  /// the start's event: the other own devices whose list names this
  /// identity join its set (§14.7 Type 23), and the list goes out when it
  /// differs from the one sent last — the first start of this version, a
  /// created identity — or is being sent in this run.
  void _identitySetAttach() {
    unawaited(Future(() {
      if (myceliumMailbox == null || identity.masterSeed == null) return;
      try {
        _identitySetJoinKnown();
        // §14.7 Type 23, D-106: device keys generated for this identity in
        // this start — it was created from a list, or this is the first start
        // of a version with one key set per identity — are unknown to the
        // other own devices of its set; they get a Type 9 with them, once.
        if (identity.deviceKeysCreatedNow &&
            _devices.values.any((d) => !d.isThisDevice)) {
          identity.deviceKeysCreatedNow = false;
          _log.info('Type 9 (§14.7 Type 23, D-106): device keys of this '
              'identity are new here — to ${_devices.length - 1} own device(s)');
          _sendTwinAnnounce(withKeys: true);
        }
        final run = _identitySetRun!;
        final signature = identitySetSignature(identitySetOwn());
        if (_identityMgr.identitySetSent() != signature ||
            run.signature == signature) {
          _identitySetSend();
        }
      } on Object catch (e) {
        _log.warn('Identity list (§14.7 Type 23): not sent at the start — $e');
      }
    }));
  }

  /// The own devices whose last list names this identity with a DeviceID,
  /// from the records of the other identities of this host: entered into
  /// this identity's set. Returns the DeviceIDs entered.
  List<String> _identitySetJoinKnown() {
    final i = identity.hdIndex;
    if (i == null) return const [];
    final added = <String>[];
    for (final s in _identitySetServices) {
      if (identical(s, this)) continue;
      for (final r in s._devices.values) {
        if (r.isThisDevice) continue;
        final u = r.identitySet?['$i'];
        if (u == null || u.length != 32 || _devices.containsKey(u)) continue;
        final now = DateTime.now();
        // D-106 (§4.4.2, §14.9.1): the device holds other keys — and so
        // another identifier — in this identity than in [s]'s; they come
        // with its Type 9 on this identity's line, not from [r].
        _devices[u] = DeviceRecord(
          deviceId: u,
          deviceName: r.deviceName,
          platform: r.platform,
          firstSeen: now,
          lastSeen: now,
          identitySet: r.identitySet,
          nodeOfDeviceHex: r.nodeOfDeviceHex,
        );
        added.add(u);
      }
    }
    if (added.isNotEmpty) {
      _saveDevices();
      _notifyDevicesChanged();
      _log.info('Identity list (§14.7 Type 23): ${added.length} own '
          'device(s) entered into the set of index $i');
    }
    return added;
  }

  /// The list for a deletion (§14.7 Type 23): naming [index] deleted, on the
  /// line of another identity of this host, to every other own device.
  /// Called by the deleting service before it goes
  /// (`broadcastIdentityDeleted`).
  void identitySetDeleting(int index) {
    for (final s in _identitySetServices) {
      if (identical(s, this) || s.myceliumMailbox == null) continue;
      s._identitySetSend(deleting: index, not: this);
      return;
    }
  }

  /// The name [newName] for [device] in every set of this host that names
  /// the same device (§14.9.1, D-99). Returns per service the DeviceID that
  /// device has there.
  Map<CleonaService, String> identitySetRenameEverywhere(
      DeviceRecord device, String newName) {
    final out = <CleonaService, String>{};
    for (final s in _identitySetServices) {
      for (final r in s._devices.values) {
        final same = device.isThisDevice
            ? r.isThisDevice
            : deviceRecordsSame(r, device);
        if (!same) continue;
        r.deviceName = newName;
        out[s] = r.deviceId;
      }
      if (out.containsKey(s)) {
        s._saveDevices();
        s._notifyDevicesChanged();
      }
    }
    return out;
  }

  /// Type 10 once per other own device (§14.7, D-99): on the line of the
  /// first identity that names it, with the renamed device's DeviceID there.
  void identitySetRenameSend(Map<CleonaService, String> records, String newName) {
    final reached = <String>{};
    for (final s in _identitySetServices) {
      final id = records[s];
      if (id == null) continue;
      for (final r in s._devices.values) {
        if (r.isThisDevice || r.deviceId.length != 32) continue;
        if (!reached.add(_deviceOf(r))) continue;
        s._sendTwinSync(
            proto.TwinSyncType.DEVICE_RENAMED,
            Uint8List.fromList(utf8.encode(
                jsonEncode({'deviceId': id, 'deviceName': newName}))),
            targetDeviceId: hexToBytes(r.deviceId));
      }
    }
  }

  /// Settings → Devices (§14.9.2, D-99): every device of every set of this
  /// host once — records of one device share its DeviceID or the node
  /// identifier of the device ([deviceRecordKeys], D-106) —, the identities
  /// it does not carry yet, and the backup in the network of each identity.
  UserDevicesView get userDevicesBuild {
    final services = _identitySetServices;
    final groups = <({Set<String> keys, List<(CleonaService, DeviceRecord)> at})>[];
    for (final s in services) {
      for (final r in s._devices.values) {
        final keys = deviceRecordKeys(r);
        final at = <(CleonaService, DeviceRecord)>[(s, r)];
        for (final g in groups.where((g) => g.keys.any(keys.contains)).toList()) {
          keys.addAll(g.keys);
          at.addAll(g.at);
          groups.remove(g);
        }
        groups.add((keys: keys, at: at));
      }
    }
    final devices = <UserDeviceView>[];
    for (final g in groups) {
      final first = g.at.firstWhere((x) => x.$2.isThisDevice,
          orElse: () => g.at.first).$2;
      final carried = {for (final x in g.at) x.$1};
      var seen = first.lastSeen;
      for (final x in g.at) {
        if (x.$2.lastSeen.isAfter(seen)) seen = x.$2.lastSeen;
      }
      devices.add(UserDeviceView(
        deviceName: first.deviceName,
        platform: first.platform,
        isThisDevice: first.isThisDevice,
        lastSeen: seen,
        lacks: [
          for (final s in services)
            if (!carried.contains(s)) s.displayName
        ],
        sentList: g.at.any((x) => x.$2.identitySet != null),
        deviceIds: {for (final x in g.at) x.$2.deviceId}.toList(),
      ));
    }
    devices.sort((a, b) => a.isThisDevice == b.isThisDevice
        ? a.deviceName.compareTo(b.deviceName)
        : (a.isThisDevice ? -1 : 1));
    return UserDevicesView(
      devices: devices,
      backups: [
        for (final s in services)
          (name: s.displayName, validUntil: s.recoveryBox?.validUntil)
      ],
    );
  }

  // ── Receiving ───────────────────────────────────────────────────────────

  /// Type 23 from the own device [from] (its DeviceID in this identity).
  Future<void> _handleTwinIdentitySet(List<int> payload, Uint8List? from) async {
    if (from == null) {
      _log.warn('Identity list (§14.7 Type 23): sender is no device of this '
          'set — discarded');
      return;
    }
    final Map<String, dynamic> j;
    try {
      j = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
    } on Object catch (e) {
      _log.warn('Identity list (§14.7 Type 23): not readable — $e');
      return;
    }
    final fromHex = bytesToHex(from);
    final piece = j['ho'];
    if (piece is Map) {
      await _identitySetPieceIn(piece.cast<String, dynamic>(), fromHex);
      return;
    }
    final received = identitySetEntriesOf(j);
    final rec = _devices[fromHex];
    if (received == null || rec == null) return;
    // §4.1 (D-106): `node` is the node identifier of the sending device, one
    // for all its identities — kept beside the identifier of this identity's
    // set, never in its place.
    final node = j['node'] as String?;
    if (node != null && node.isNotEmpty) rec.nodeOfDeviceHex ??= node;
    final device = _deviceOf(rec);
    final map = {
      for (final e in received) '${e.index}': e.active ? e.deviceIdHex : ''
    };
    // The list on every record of that device, in every identity.
    for (final s in _identitySetServices) {
      var changed = false;
      for (final r in s._devices.values) {
        if (identical(r, rec) || deviceRecordsSame(r, rec)) {
          r.identitySet = map;
          r.nodeOfDeviceHex ??= rec.nodeOfDeviceHex;
          r.lastSeen = DateTime.now();
          changed = true;
        }
      }
      if (changed) s._saveDevices();
    }
    final mgr = _identityMgr;
    final own = identitySetOwn();
    final services = {
      for (final s in _identitySetServices)
        if (s.identity.hdIndex != null) s.identity.hdIndex!: s
    };
    final byIndex = {for (final e in received) e.index: e};
    final plan = identitySetPlan(
      received: received,
      carried: {
        for (final MapEntry(key: i, value: s) in services.entries)
          i: (
            history: s._identitySetHistory,
            senderInSet: byIndex[i] != null &&
                s._devices.containsKey(byIndex[i]!.deviceIdHex),
          )
      },
      deleted: mgr.deletedHdIndices().toSet(),
      own: own,
    );
    _log.info('Identity list (§14.7 Type 23) from device '
        '${CleonaService._hexShort(from)}: ${received.length} entr'
        '${received.length == 1 ? "y" : "ies"} — create ${plan.create}, '
        'delete ${plan.delete}, join ${plan.join}, hand over '
        '${plan.handOver}${plan.answer ? ", answered" : ""}');
    for (final i in plan.noteDeleted) {
      mgr.markHdIndexDeleted(i);
    }
    for (final i in plan.delete) {
      mgr.markHdIndexDeleted(i);
      final s = services[i]!;
      s._log.warn('Identity list (§14.7 Type 23): this identity was deleted '
          'on another own device — local copy is being cleared away');
      s._wipeLocalIdentityData();
      s.onIdentityDeletedRemotely?.call(s.identity.userIdHex);
    }
    for (final i in plan.join) {
      final s = services[i]!;
      final u = byIndex[i]!.deviceIdHex;
      s._identitySetJoinKnown();
      if (!s._devices.containsKey(u)) continue;
      if (plan.handOver.contains(i)) {
        _identitySetHandOver(s, u);
      } else if (!_identitySetRun!.handedOver.contains('$i#$device')) {
        s._identitySetMergeTo(hexToBytes(u));
      }
    }
    for (final i in plan.create) {
      await _identitySetCreate(byIndex[i]!);
    }
    if (plan.answer) _identitySetSend(only: {device});
  }

  /// Creates the identity [e] names from the seed (§4.5.1) and has the host
  /// start it; its attachment fills its set. Its first bundle is due from
  /// the creation time [e] names (§13.3.4).
  Future<CleonaService?> _identitySetCreate(IdentitySetEntry e) async {
    final Identity created;
    try {
      created = await _identityMgr.createIdentityAtIndex(
          e.index, e.name.isEmpty ? '${e.index + 1}' : e.name);
    } on Object catch (err) {
      _log.warn('Identity list (§14.7 Type 23): index ${e.index} not '
          'created — $err');
      return null;
    }
    if (e.createdAtMs > 0) {
      _identitySetFirstBundleAt['${identity.baseDir}#${e.index}'] =
          e.createdAtMs;
    }
    _log.event('Identity list (§14.7 Type 23): identity at index ${e.index} '
        'created from the words (it was created on another own device)');
    final start = onIdentityFound;
    if (start == null) {
      _log.warn('Identity list (§14.7 Type 23): no host listener — index '
          '${e.index} starts with the next start');
      return null;
    }
    try {
      await start(created);
    } on Object catch (err) {
      _log.error('Identity list (§14.7 Type 23): index ${e.index} did not '
          'start ($err) — it starts with the next start');
      return null;
    }
    for (final s in _identitySetServices) {
      if (s.identity.hdIndex == e.index) return s;
    }
    return null;
  }

  /// One identity created twice (§14.7 Type 23): its contacts, groups and
  /// channels to the own device [to] that just joined its set.
  void _identitySetMergeTo(Uint8List to) {
    var n = 0;
    for (final c in _contacts.values) {
      if (c.status != 'accepted') continue;
      _sendTwinContactAdded(c, to: to);
      n++;
    }
    for (final g in _groups.values) {
      _sendTwinGroupCreated(g, to: to);
      n++;
    }
    for (final c in _channels.values) {
      _sendTwinChannelJoined(c, to: to);
      n++;
    }
    if (n > 0) {
      _log.info('Identity list (§14.7 Type 23): $n contact(s), group(s) and '
          'channel(s) to device ${CleonaService._hexShort(to)}');
    }
  }

  /// The handover of [y] (§14.6.2) to the own device [toHex] (its DeviceID
  /// in [y]'s set), in pieces of at most 32 KB on THIS identity's line.
  void _identitySetHandOver(CleonaService y, String toHex) {
    final i = y.identity.hdIndex!;
    final body = enrolBodyOf(y._enrolHandoverBuild());
    final id = bytesToHex(SodiumFFI().randomBytes(8));
    final count = (body.length + kIdentitySetPieceRaw - 1) ~/ kIdentitySetPieceRaw;
    // The device on THIS line: the record of [toHex] in [y]'s set names it.
    final r = y._devices[toHex];
    String? lineDevice;
    for (final d in _devices.values) {
      if (r != null && deviceRecordsSame(d, r)) {
        lineDevice = d.deviceId;
      }
    }
    if (lineDevice == null) return;
    _identitySetRun!.handedOver.add('$i#${_deviceOf(r!)}');
    for (var k = 0; k < count; k++) {
      final end = (k + 1) * kIdentitySetPieceRaw;
      final slice = body.sublist(
          k * kIdentitySetPieceRaw, end > body.length ? body.length : end);
      _sendTwinSync(
          proto.TwinSyncType.IDENTITY_SET,
          Uint8List.fromList(utf8.encode(jsonEncode({
            'v': 1,
            'ho': {
              'i': i,
              'id': id,
              'k': k,
              'of': count,
              'b': base64Encode(slice),
            },
          }))),
          targetDeviceId: hexToBytes(lineDevice));
    }
    _log.info('Identity list (§14.7 Type 23): handover of index $i '
        '(${body.length} B) in $count piece(s) to device '
        '${toHex.substring(0, 8)}');
  }

  /// A handover piece: put together per sender and handover; a complete one
  /// is taken over by the identity it names, as at enrolment (§14.6.2).
  Future<void> _identitySetPieceIn(
      Map<String, dynamic> piece, String fromHex) async {
    final i = piece['i'], id = piece['id'], k = piece['k'], of = piece['of'];
    final b = piece['b'];
    if (i is! int || id is! String || k is! int || of is! int || b is! String ||
        k < 0 || k >= of || of > 256) {
      _log.warn('Identity list (§14.7 Type 23): handover piece not readable');
      return;
    }
    final run = _identitySetRun;
    if (run == null) return;
    final key = '$fromHex#$id';
    final have = run.pieces.putIfAbsent(key, () => {});
    have[k] = base64Decode(b);
    if (have.length < of) {
      _log.info('Identity list (§14.7 Type 23): handover of index $i — '
          '${have.length} of $of piece(s)');
      return;
    }
    run.pieces.remove(key);
    final all = BytesBuilder(copy: false);
    for (var x = 0; x < of; x++) {
      all.add(have[x]!);
    }
    CleonaService? y;
    for (final s in _identitySetServices) {
      if (s.identity.hdIndex == i) y = s;
    }
    if (y == null || y.myceliumMailbox == null) {
      _log.warn('Identity list (§14.7 Type 23): handover of index $i — the '
          'identity is not carried here — not taken over');
      return;
    }
    y._enrolTakeOver(all.takeBytes());
  }
}
