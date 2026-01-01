// What a device holds of a group or channel on the shared key (v4_2
// §16.2.5): the generations it reads, the position it posts at, its keepers,
// its author keys, and what it has collected or refused under each channel
// value. Pure data with its JSON form — the service keeps one per group or
// channel in the store area [kSharedKeyArea] (`cleona_service_shared_key.dart`),
// inside the encrypted message store (§4.5.3, §21.4.2).
//
// Forward secrecy, honestly (§16.2.1): a device keeps the day and step keys
// of the last 7 UTC days ([kKeepDays]) and deletes older ones ([prune]); it
// never holds anything that derives backward.

import 'dart:typed_data';

import 'package:cleona/core/util/hex.dart' show bytesToHex, hexToBytes;
import 'package:mycelium/channel_chain.dart' as chain;

const String kSharedKeyArea = 'shared_key';

/// Posts whose placing has not reached two keepers (§16.2.5 "Delivery
/// state"): deposited again at the edges of §8.2 (§9.3).
const String kSharedKeyOutArea = 'shared_key_out';

/// Capability notices received (UserID → bits and class) and sent (UserID →
/// the value last sent), §16.2.5 "Mixed operation within 4.2".
const String kCapabilityArea = 'capabilities';
const String kCapabilitySentArea = 'capability_sent';

/// Capability bits of the notice (§16.2.5 "Mixed operation within 4.2").
const int kCapMemberList = 1;
const int kCapSharedKey = 2;
/// §16.2.2 (S407 group profile): reads a change of name, description and
/// image of a group or private channel (`ChatConfigUpdate.profile`).
const int kCapGroupProfile = 4;
const int kCapsBuilt = kCapMemberList | kCapSharedKey | kCapGroupProfile;

/// Device class of the notice.
const int kClassDesktop = 1;
const int kClassPhone = 2;

/// §16.2.1: on the shared key from 17 members on; back to pairwise legs only
/// at 12 or fewer.
const int kSharedKeyFrom = 17;

/// §16.2.1 (table, "anonymous polls (§18.4)": pairwise "possible", shared
/// key "not possible"), §18.4.3: an anonymous poll needs pairwise legs — on
/// the shared key every post carries the author's signature (§4.4.3), so a
/// vote is attributed. Not possible on the shared key, nor from
/// [kSharedKeyFrom] members on, where the owner switches to it.
bool anonymousPollPossibleFor({required int members, required bool onSharedKey}) =>
    !onSharedKey && members < kSharedKeyFrom;
const int kPairwiseAtMost = 12;

/// At most this many keepers in a list (§16.2.5 "Keepers").
const int kKeepersAtMost = 5;

String _h(Uint8List b) => bytesToHex(b);
Uint8List? _b(Object? s) => s is String && s.isNotEmpty ? hexToBytes(s) : null;

class SharedGeneration {
  final int number;
  final Uint8List id;

  /// `r_g` — only on the device that drew it; never leaves it.
  Uint8List? root;
  final Uint8List keeperKey; // A_g
  final Uint8List generationPk;

  /// `W_g` — owner and admins only.
  Uint8List? generationSeed;

  /// Day keys held, by UTC day.
  final Map<int, Uint8List> dayKeys;

  /// For a day whose day key is not held (the day of a joining): the lowest
  /// step held, `(j, S_g(d, j))`.
  final Map<int, (int, Uint8List)> stepFloor;

  /// The newest `(d, j)` this device knows — where it posts.
  int day;
  int step;

  /// The own author key of this generation and its certificate.
  Uint8List? authorPk;
  Uint8List? authorSk;
  Uint8List? certificate;

  SharedGeneration({
    required this.number,
    required this.id,
    this.root,
    required this.keeperKey,
    required this.generationPk,
    this.generationSeed,
    Map<int, Uint8List>? dayKeys,
    Map<int, (int, Uint8List)>? stepFloor,
    required this.day,
    this.step = 0,
    this.authorPk,
    this.authorSk,
    this.certificate,
  })  : dayKeys = dayKeys ?? {},
        stepFloor = stepFloor ?? {};

  String get key => '$number:${_h(id)}';

  /// `S_g(d, j)`, derived forward from what is held; `null` when only a later
  /// step or day is held (never backward) or nothing of that day.
  Uint8List? stepKey(int d, int j) {
    final floor = stepFloor[d];
    if (floor != null) return chain.stepKeyAt(floor.$2, floor.$1, j);
    final dk = dayKey(d);
    if (dk == null) return null;
    return chain.stepKeyAt(chain.stepKeyFirst(dk), 0, j);
  }

  /// `D_g(d)` from the newest held day key at or before [d].
  Uint8List? dayKey(int d) {
    final held = dayKeys.keys.where((x) => x <= d).toList()..sort();
    if (held.isEmpty) return null;
    return chain.dayKeyAt(dayKeys[held.last]!, held.last, d);
  }

  /// Whether a post at `(d, j)` lies beyond the position — then the position
  /// moves there (a member that sees a later day or step derives forward).
  void seen(int d, int j) {
    if (d > day || (d == day && j > step)) {
      day = d;
      step = j;
    }
  }

  /// The collect key pair of day [d].
  ({Uint8List publicKey, Uint8List secretKey}) collect(int d) =>
      chain.collectPair(keeperKey, d);

  /// The channel value of day [d].
  Uint8List value(int d) =>
      chain.channelValue(collect(d).publicKey, generationPk);

  /// Deletes the keys of days before the last 7 (§16.2.5): the earliest kept
  /// day key is derived forward first, so the window stays readable.
  void prune(int today) {
    final first = today - chain.kKeepDays + 1;
    final older = dayKeys.keys.where((d) => d < first).toList()..sort();
    if (older.isNotEmpty && !dayKeys.containsKey(first)) {
      final k = chain.dayKeyAt(dayKeys[older.last]!, older.last, first);
      if (k != null) dayKeys[first] = k;
    }
    dayKeys.removeWhere((d, _) => d < first);
    stepFloor.removeWhere((d, _) => d < first);
    if (root != null && day < first) root = null;
  }

  /// Whether every key of it is older than the last 7 days.
  bool spent(int today) =>
      dayKeys.isEmpty && stepFloor.isEmpty && day < today - chain.kKeepDays + 1;

  Map<String, dynamic> toJson() => {
        'n': number,
        'id': _h(id),
        if (root != null) 'r': _h(root!),
        'a': _h(keeperKey),
        'pk': _h(generationPk),
        if (generationSeed != null) 'w': _h(generationSeed!),
        'dk': {for (final e in dayKeys.entries) '${e.key}': _h(e.value)},
        'sf': {
          for (final e in stepFloor.entries) '${e.key}': [e.value.$1, _h(e.value.$2)]
        },
        'd': day,
        'j': step,
        if (authorPk != null) 'apk': _h(authorPk!),
        if (authorSk != null) 'ask': _h(authorSk!),
        if (certificate != null) 'cert': _h(certificate!),
      };

  static SharedGeneration fromJson(Map<String, dynamic> j) => SharedGeneration(
        number: j['n'] as int,
        id: hexToBytes(j['id'] as String),
        root: _b(j['r']),
        keeperKey: hexToBytes(j['a'] as String),
        generationPk: hexToBytes(j['pk'] as String),
        generationSeed: _b(j['w']),
        dayKeys: {
          for (final e in (j['dk'] as Map? ?? {}).entries)
            int.parse(e.key as String): hexToBytes(e.value as String)
        },
        stepFloor: {
          for (final e in (j['sf'] as Map? ?? {}).entries)
            int.parse(e.key as String): (
              (e.value as List)[0] as int,
              hexToBytes((e.value as List)[1] as String)
            )
        },
        day: j['d'] as int,
        step: j['j'] as int? ?? 0,
        authorPk: _b(j['apk']),
        authorSk: _b(j['ask']),
        certificate: _b(j['cert']),
      );
}

class SharedKeyState {
  final String gid;

  /// The construction (§16.2.1): `true` on the shared key.
  bool on;

  /// Every generation still readable, by [SharedGeneration.key].
  final Map<String, SharedGeneration> generations;

  /// The generation in force: of two with the same number the smaller
  /// identifier holds (§16.2.5 "Leaving and removal").
  String? holding;

  /// The newest keeper list read, packed addresses in order, and its version.
  List<Uint8List> keepers;
  int keepersVersion;

  /// The members served on the shared key (UserIDs, hex) — every other one
  /// gets pairwise legs.
  Set<String> served;

  /// value hex → entry hashes (hex) held or refused under it (§16.0 root).
  final Map<String, Set<String>> held;

  /// value hex → UTC day of the value (for pruning and the question).
  final Map<String, int> valueDay;

  /// Values whose day is closed: a question after the day's end was "same".
  final Set<String> closed;

  /// Owner and admin: member → key of the generation it was given.
  final Map<String, String> given;

  /// Owner and admin: member → the author key it named (hex).
  final Map<String, String> named;

  /// Deferred inline images: object entry hash → message id.
  final Map<String, String> objects;

  /// Own author key pairs named but not yet certified (public hex → secret
  /// hex): the one named in the acceptance or in the last post.
  final Map<String, String> authorKeys;

  SharedKeyState({
    required this.gid,
    this.on = false,
    Map<String, SharedGeneration>? generations,
    this.holding,
    List<Uint8List>? keepers,
    this.keepersVersion = 0,
    Set<String>? served,
    Map<String, Set<String>>? held,
    Map<String, int>? valueDay,
    Set<String>? closed,
    Map<String, String>? given,
    Map<String, String>? named,
    Map<String, String>? objects,
    Map<String, String>? authorKeys,
  })  : authorKeys = authorKeys ?? {},
        generations = generations ?? {},
        keepers = keepers ?? [],
        served = served ?? {},
        held = held ?? {},
        valueDay = valueDay ?? {},
        closed = closed ?? {},
        given = given ?? {},
        named = named ?? {},
        objects = objects ?? {};

  SharedGeneration? get current =>
      holding == null ? null : generations[holding];

  /// Takes [g] in; returns whether it holds now (§16.2.5: a higher number,
  /// or the same number with a smaller identifier).
  bool adopt(SharedGeneration g) {
    generations[g.key] = generations[g.key] ?? g;
    final c = current;
    if (c == null ||
        g.number > c.number ||
        (g.number == c.number && _less(g.id, c.id))) {
      holding = g.key;
      return true;
    }
    return false;
  }

  SharedGeneration? byHead(int number, Uint8List id) =>
      generations['$number:${_h(id)}'];

  /// Drops keys and bookkeeping older than the last 7 days.
  void prune(int today) {
    for (final g in generations.values) {
      g.prune(today);
    }
    generations.removeWhere((k, g) => k != holding && g.spent(today));
    final first = today - chain.kKeepDays;
    final old = [
      for (final e in valueDay.entries)
        if (e.value < first) e.key
    ];
    for (final v in old) {
      valueDay.remove(v);
      held.remove(v);
      closed.remove(v);
    }
  }

  Map<String, dynamic> toJson() => {
        'gid': gid,
        'on': on,
        'gens': {for (final e in generations.entries) e.key: e.value.toJson()},
        if (holding != null) 'holding': holding,
        'keepers': [for (final k in keepers) _h(k)],
        'kv': keepersVersion,
        'served': served.toList(),
        'held': {for (final e in held.entries) e.key: e.value.toList()},
        'vday': valueDay,
        'closed': closed.toList(),
        'given': given,
        'named': named,
        'objects': objects,
        'authorKeys': authorKeys,
      };

  static SharedKeyState fromJson(Map<String, dynamic> j) => SharedKeyState(
        gid: j['gid'] as String,
        on: j['on'] as bool? ?? false,
        generations: {
          for (final e in (j['gens'] as Map? ?? {}).entries)
            e.key as String:
                SharedGeneration.fromJson(Map<String, dynamic>.from(e.value as Map))
        },
        holding: j['holding'] as String?,
        keepers: [for (final k in (j['keepers'] as List? ?? [])) hexToBytes(k as String)],
        keepersVersion: j['kv'] as int? ?? 0,
        served: {for (final s in (j['served'] as List? ?? [])) s as String},
        held: {
          for (final e in (j['held'] as Map? ?? {}).entries)
            e.key as String: {for (final h in e.value as List) h as String}
        },
        valueDay: {
          for (final e in (j['vday'] as Map? ?? {}).entries)
            e.key as String: e.value as int
        },
        closed: {for (final s in (j['closed'] as List? ?? [])) s as String},
        given: Map<String, String>.from(j['given'] as Map? ?? {}),
        named: Map<String, String>.from(j['named'] as Map? ?? {}),
        objects: Map<String, String>.from(j['objects'] as Map? ?? {}),
        authorKeys: Map<String, String>.from(j['authorKeys'] as Map? ?? {}),
      );
}

bool _less(Uint8List a, Uint8List b) {
  for (var i = 0; i < a.length && i < b.length; i++) {
    if (a[i] != b[i]) return a[i] < b[i];
  }
  return a.length < b.length;
}
