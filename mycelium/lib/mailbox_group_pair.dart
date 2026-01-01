/// The group pairs of a mailbox (V4.2 §4.3 "`s_AB` for co-members who are
/// not contacts", §8.2, §15.7, §16.2.2, D-36; owner decision B-3, G2).
///
/// Two members of a group who are not contacts of each other still exchange
/// pairwise legs (§16.2). Their `s_AB` is drawn by the inviter and travels
/// sealed in the invitation leg to each of the two; the formula of `K_AB` is
/// unchanged (§4.3). From it follow the pair's codes (step 3, §8.1) and, with
/// the first day-key notice the pair sends at the edge "new group pair",
/// its post box (step 4, §8.2).
///
/// ── A GROUP PAIR IS NOT A CONTACT ───────────────────────────────────────
///
/// It lives in its own store (`memory_group_pair.dart`, E5 = b), not in the
/// contact list — so [Mailbox.contacts], the contact seats
/// (`host_contact_seats.dart`: a group pair never takes a fixed seat, §5.2),
/// the search call and the three route sources (`mailbox.dart`) never see
/// it. It has no route: its legs go by code and post box only. What it may
/// carry into the application is the application's gate (§15.7: group types
/// naming a shared group); mycelium only knows WHO it is.
///
/// ── WHEN IT ARISES AND ENDS ─────────────────────────────────────────────
///
/// A seed that arrives before the pair can be formed WAITS ([groupPairSeed])
/// — before the own explicit join, or before the co-member's self-signed
/// address is known (§16.2.2 "only then are its group pairs formed"). The
/// application forms the pair ([groupPairRemember]) and ends it per group
/// ([groupPairLeave]); with the last group the pair, its codes and its day
/// keys are gone.
///
/// A separate file because `mailbox.dart` stands at the line limit; it gets
/// by with the public side of [Mailbox].
library;

import 'dart:typed_data';

import 'package:mycelium/card_address.dart';
import 'package:mycelium/envelope.dart' show Address;
import 'package:mycelium/group_member.dart';
import 'package:mycelium/history.dart' show HistoryEntry;
import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/mailbox.dart';
import 'package:mycelium/mailbox_outbound.dart' show MailboxOutbound;
import 'package:mycelium/mailbox_pair.dart';
import 'package:mycelium/mailbox_start.dart' show MailboxDetails;
import 'package:mycelium/memory.dart' show MemoryError, kDayKeyAtMost;
import 'package:mycelium/memory_enforcer.dart' show legacyDataClear;
import 'package:mycelium/memory_group_pair.dart';
import 'package:mycelium/message.dart' show Inbound, Outbound;
import 'package:mycelium/neighbour_list.dart';
import 'package:mycelium/pair.dart';

export 'package:mycelium/memory_group_pair.dart' show GroupPair;

extension MailboxGroupPair on Mailbox {
  GroupPairStore? get _store => _stores[this];

  /// Opens the store of this identity — when the mailbox is created. A store
  /// of a foreign version is removed by the enforcer (no conversion); one
  /// that cannot be read is reported and replaced by an empty one: the pairs
  /// arise again with the next membership update that carries their seeds.
  void groupPairOpen(MailboxDetails a) {
    legacyDataClear(
        directory: a.directory,
        fileName: kFileGroupPairs,
        runningVersion: kVersionGroupPairs,
        key: a.key,
        report: report);
    try {
      _stores[this] = GroupPairStore.open(a.directory, a.key);
    } on MemoryError catch (e) {
      report?.call('group-pair store not readable — starts empty: $e');
      a.directory.createSync(recursive: true);
      _stores[this] = GroupPairStore.empty(a.directory, a.key);
    }
    identity.messages.onReceiptToMailbox = groupPairDayKeysAcked;
  }

  /// All group pairs of THIS identity.
  List<GroupPair> get groupPairs => [...?_store?.pairs.values];

  /// The group pair with [identifier] (hex), or `null`.
  GroupPair? groupPairOrNull(String identifier) => _store?.pairs[identifier];

  /// Contacts with `s_AB` and group pairs — everyone this identity forms a
  /// `K_AB` with (§4.3), for codes and the `0x23`.
  List<({Address address, Uint8List s})> get pairPartners => [
        for (final k in contacts)
          if (k.pairRandom case final s?)
            if (k.address.foundingEd25519Pk != null) (address: k.address, s: s),
        for (final p in groupPairs)
          if (p.address.foundingEd25519Pk != null)
            (address: p.address, s: p.pairRandom),
      ];

  /// An `s_AB` for the co-member [identifier] in [group] arrived in an
  /// invitation leg (§16.2.2). It waits until [groupPairRemember] forms the
  /// pair or adds [group] to it. A contact keeps its own `s_AB` and ignores
  /// it; a group that already carries the pair keeps its seed.
  void groupPairSeed(Uint8List group, Uint8List identifier, Uint8List s) {
    final store = _store;
    final id = _hex(identifier);
    final g = _hex(group);
    if (store == null || s.length != kPairRandomLength) return;
    if (contactOrNull(id) != null) return;
    if (store.pairs[id]?.groupSeeds.containsKey(g) ?? false) return;
    store.seeds[GroupPairStore.seedKey(g, id)] = s;
    store.save();
  }

  /// Forms the group pair with [a] for [group], or adds [group] to an
  /// existing one — called by the application after the own explicit join,
  /// with the co-member's address it checked (`group_member.dart`). Needs the
  /// waiting seed for exactly this group and co-member (unless [group]
  /// already carries the pair). `false`: no pair for [group] — a contact, no
  /// seed, or the own identity.
  ///
  /// EDGE (§8.1, §8.2): a new pair brings a code, and it gets the own day
  /// keys at once ("new contact or group pair"); a new group can change the
  /// pair's `s_AB` ([GroupPair.pairRandom]), and with it the code.
  bool groupPairRemember(Address a, Uint8List group,
      {List<CardAddress> neighbours = const []}) {
    final store = _store;
    final id = identifierFrom(a);
    final g = _hex(group);
    if (store == null || id == ownIdentifier || contactOrNull(id) != null) {
      return false;
    }
    final known = store.pairs[id];
    final s = store.seeds.remove(GroupPairStore.seedKey(g, id));
    if (known != null) {
      final before = _hex(known.pairRandom);
      if (s != null) known.groupSeeds.putIfAbsent(g, () => s);
      if (!known.groupSeeds.containsKey(g)) return false;
      _adopt(known, a);
      _neighboursTake(known, neighbours);
      store.save();
      if (_hex(known.pairRandom) != before) node.codeRoute.codesChanged();
      return true;
    }
    if (s == null) return false;
    store.pairs[id] =
        GroupPair(address: a, groupSeeds: {g: s}, neighbours: neighbours);
    store.save();
    report?.call('group pair ${id.substring(0, 8)} formed');
    node.codeRoute.codesChanged();
    dayKeyDistribute(only: a);
    return true;
  }

  /// The application's call per co-member entry of [group] (§16.2.2): the
  /// entry must carry the co-member's own signature (`group_member.dart`,
  /// E3); then the pair is formed or extended ([groupPairRemember]).
  /// `address == null`: the entry does not prove itself — no pair (the
  /// application shows it, proposal Z-5). `paired == false` with an address:
  /// a contact, or no seed for it yet.
  ({Address? address, bool paired}) groupPairFromEntry(Uint8List group,
      Uint8List addressWire, Uint8List ed, Uint8List dsa,
      {Uint8List? neighboursWire}) {
    final a = groupMemberCheck(group, addressWire, ed, dsa);
    if (a == null) return (address: null, paired: false);
    return (
      address: a,
      paired: groupPairRemember(a, group,
          neighbours: groupMemberNeighboursRead(neighboursWire ?? Uint8List(0))),
    );
  }

  /// [group] no longer carries the co-members outside [keep] (identifiers,
  /// hex; `null`: none of them — the own identity left the group). A pair
  /// without any group ends: its codes and day keys are gone (§4.3 "ends
  /// when no shared group carries it"). Waiting seeds of [group] outside
  /// [keep] go too. Returns the number of pairs that ended.
  int groupPairLeave(Uint8List group, {Set<String>? keep}) {
    final store = _store;
    if (store == null) return 0;
    final g = _hex(group);
    var changed = false;
    var codes = false;
    final ended = <String>[];
    for (final e in store.pairs.entries) {
      if (keep != null && keep.contains(e.key)) continue;
      if (!e.value.groupSeeds.containsKey(g)) continue;
      final before = _hex(e.value.pairRandom);
      e.value.groupSeeds.remove(g);
      changed = true;
      if (e.value.groupSeeds.isEmpty) {
        ended.add(e.key);
      } else if (_hex(e.value.pairRandom) != before) {
        codes = true; // another group's seed is the pair's `s_AB` now
      }
    }
    for (final id in ended) {
      store.pairs.remove(id);
      histories.drop(id); // its history ends with the pair (S401, U-11)
      report?.call('group pair ${id.substring(0, 8)} ended');
    }
    final before = store.seeds.length;
    store.seeds.removeWhere((k, _) =>
        k.startsWith('$g:') && (keep == null || !keep.contains(k.substring(g.length + 1))));
    if (changed || store.seeds.length != before) store.save();
    if (ended.isNotEmpty || codes) node.codeRoute.codesChanged();
    return ended.length;
  }

  /// Sends [content] to the group pair [identifier] — by code and post box
  /// only: a group pair has no route and no search call (`mailbox.dart`,
  /// "exactly three sources"). Throws [MailboxError] for an unknown pair.
  Outbound groupPairSend(String identifier, Uint8List content) {
    final p = groupPairOrNull(identifier) ??
        (throw MailboxError('no group pair $identifier'));
    // Through the one entrance of the outbound: the placing of this leg is
    // remembered on its own entry (`mailbox_outbound.dart`, §9.3).
    final outbound = dispatch(p.address, content, null);
    historyFor(p.address).append(HistoryEntry(
      identifier: outbound.identifier,
      outgoing: true,
      content: content,
      instant: DateTime.now(),
      state: outbound.state,
    ));
    return outbound;
  }

  /// An inbound from a group pair: a newer address of it is adopted
  /// ([Address.adopt]), its identifier goes into the identity's received
  /// memory (`mailbox_inbound.dart`, B2-3 variant A; §20.2). The check
  /// against the second copy runs above, at the one entrance of the
  /// inbound — for every sender, this one included.
  bool groupPairInbound(Inbound e) {
    final p = groupPairOrNull(identifierFrom(e.from));
    if (p == null) return false;
    if (_adopt(p, e.from)) _store!.save();
    // The content is the application's (§21.4.2); of the delivery only
    // the identifier is kept — no peer, no time (V-2 = b, V-4).
    histories.store.incomingKeep(e.identifier);
    return true;
  }

  /// A day-key notice of a group pair (§8.2). `false`: not a group pair.
  bool groupPairNoticeAccept(Inbound e, int today) {
    final p = groupPairOrNull(identifierFrom(e.from));
    if (p == null || e.kind != kinds.kDayKey) return false;
    final first = p.dayKey.isEmpty;
    p.dayKey = dayKeysMerge(p.dayKey, dayKeyRead(e.content), today);
    _store!.save();
    // EDGE "the pair's first day keys arrived" (§8.2, S398 N-1a): the
    // counterpart formed the pair after our notice, which then found no code
    // and was lost. One notice, no clock; only while ours has no receipt.
    if (first && p.dayKeySent == null) dayKeyDistribute(only: p.address);
    return true;
  }

  /// A group pair's fixed neighbours arrived sealed (§9.2). `true` if adopted.
  bool groupPairNeighbours(Address from, List<CardAddress> list) {
    final p = groupPairOrNull(identifierFrom(from));
    if (p == null || !_neighboursTake(p, list)) return false;
    _store!.save();
    return true;
  }

  /// What another own device holds of the group pair [identifier] (§14.7
  /// Type 6): the co-member's day keys and fixed neighbours. `false`: no such
  /// pair here.
  bool groupPairTakeOver(String identifier, int today,
      {Map<int, Uint8List>? dayKey, List<CardAddress>? neighbours}) {
    final p = groupPairOrNull(identifier);
    if (p == null) return false;
    if (dayKey != null) p.dayKey = dayKeysMerge(p.dayKey, dayKey, today);
    if (neighbours != null) _neighboursTake(p, neighbours);
    _store!.save();
    return true;
  }

  /// The group pairs whose own day keys are due (§8.2: none yet, or the last
  /// shipment at least [kDayKeyInterval] back); [only]: just that one.
  List<GroupPair> groupPairsDue({Address? only, required DateTime at}) => [
        for (final p in groupPairs)
          if ((only == null || p.address.sameIdentity(only)) &&
              (p.dayKeySent == null ||
                  at.difference(p.dayKeySent!) >= kDayKeyInterval))
            p,
      ];

  /// Sends the day-key notice [content] to [p]. It counts as sent only with
  /// its receipt (§9.2; S398 N-1a: noted on leaving, a lost first notice was
  /// never sent again) — until then [p] stays due at every edge.
  void groupPairDayKeysSend(GroupPair p, Uint8List content) {
    final out = node.send(content, p.address, null,
        forField: identity, kind: kinds.kDayKey);
    final id = identifierFrom(p.address);
    (_dayKeyOpen[this] ??= {})[_hex(out.identifier)] = id;
    report?.call('day keys to group pair ${id.substring(0, 8)} sent '
        '(${_hex(out.identifier).substring(0, 6)}) — counted with its receipt');
  }

  /// A receipt of this identity (`Messages.onReceiptToMailbox`): if it is
  /// one of a day-key notice, the pair's notice counts as sent now. Held in
  /// memory only — after a restart the pair is due again, and the start edge
  /// sends anew.
  void groupPairDayKeysAcked(Outbound out) {
    final open = _dayKeyOpen[this];
    final id = open?.remove(_hex(out.identifier));
    final p = id == null ? null : groupPairOrNull(id);
    if (p == null) return;
    p.dayKeySent = out.acknowledgedAt ?? DateTime.now();
    _store!.save();
    // The pair has our day keys: every other notice to it still under way is
    // superseded and ends — evidence of THIS recipient (`node_helpers.dart`).
    // A paused one resumed later and sent its keys once more (S398: a lost
    // first notice, overtaken by the answer edge, went out in the idle).
    for (final n in [...open!.entries.where((e) => e.value == id)]) {
      open.remove(n.key);
      node.shipmentEnd(n.key);
    }
    report?.call('day keys to group pair ${id!.substring(0, 8)} receipted');
  }

  bool _adopt(GroupPair p, Address fresh) {
    if (!Address.adopt(p.address, fresh)) return false;
    p.address = fresh;
    return true;
  }

  bool _neighboursTake(GroupPair p, List<CardAddress> list) {
    final clean = neighbourListClean(list);
    if (clean.isEmpty || neighbourListEqual(p.neighbours, clean)) return false;
    p.neighbours = clean;
    return true;
  }
}

/// [held] and [fresh] day keys together, trimmed to yesterday ..
/// today + [kDayKeyDays] and at most [kDayKeyAtMost] (`mailbox_pair.dart`).
Map<int, Uint8List> dayKeysMerge(
    Map<int, Uint8List> held, Map<int, Uint8List> fresh, int today) {
  final all = {...held, ...fresh}
    ..removeWhere((t, _) => t < today - 1 || t > today + kDayKeyDays);
  final days = all.keys.toList()..sort();
  return {for (final t in days.take(kDayKeyAtMost)) t: all[t]!};
}

final Expando<GroupPairStore> _stores = Expando('groupPairStore');

/// Per mailbox: identifier (hex) of a day-key notice without receipt yet ->
/// the group pair it went to.
final Expando<Map<String, String>> _dayKeyOpen = Expando('dayKeyOpen');

String _hex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
