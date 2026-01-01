/// The group pairs of an identity (V4.2 §4.3 "`s_AB` for co-members who are
/// not contacts", §16.2.2, D-36) — in a store file of its OWN, next to the
/// mailbox memory (owner decision B-3, E5 = b).
///
/// ── WHY A SEPARATE FILE ─────────────────────────────────────────────────
///
/// A field in the contact would raise the memory's version (`memory.dart`),
/// and the enforcer (`memory_enforcer.dart`) would remove the memory of every
/// installed device — `s_AB`, day keys, routes of EVERY contact (W-a). A
/// store of its own starts empty on a device that never had one, and that is
/// the correct state for it. It also keeps apart what must stay apart: a
/// group pair is NOT a contact (§12.5) — it carries only group types, never
/// takes a fixed seat (§5.2), and ends with the last shared group.
///
/// ── WHAT IT HOLDS ───────────────────────────────────────────────────────
///
///  * per GROUP PAIR: the co-member's address as it signed it on joining
///    (with its rotation chain), the co-member's fixed neighbours, its day
///    keys, when the own day keys last went to it, and the groups that carry
///    the pair, each with the `s_AB` its inviter drew ([GroupPair]);
///  * per WAITING seed: an `s_AB` that arrived in an invitation leg before
///    the pair could be formed — before the own explicit join, or before the
///    co-member's self-signed address was known (§16.2.2). It is no pair: no
///    code, no day key, nothing is sent under it.
///
/// ```
/// version (1 B) = 1
/// pairs: count (u16) | per pair: address (Address.length) + its chain
///                    | neighbours (count 0..3 + addresses)
///                    | day keys: count (1 B), per day u32 + 32 B
///                    | own day keys last sent (u64 ms, 0 = never)
///                    | groups: count (1 B), per group length (1) + bytes
///                    |         + that group's s_AB 32 B
/// seeds: count (u16) | per seed: group length (1) + bytes
///                    | identifier 32 B | s_AB 32 B
/// ```
///
/// Encrypted and written atomically like the memory ([FileEncryption]).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/crypto/file_encryption.dart';
import 'package:mycelium/card_address.dart';
import 'package:mycelium/envelope.dart' show Address;
import 'package:mycelium/memory_contact.dart'
    show addressChainRead, addressChainWrite, kDayKeyAtMost;
import 'package:mycelium/memory_invitation.dart' show MemoryError, Reader;
import 'package:mycelium/neighbour_list.dart';
import 'package:mycelium/pair.dart' show kPairRandomLength;

/// The file name — [FileEncryption] appends `.enc`.
const String kFileGroupPairs = 'group-pairs';

/// The layout version of this store — its own, independent of the memory.
const int kVersionGroupPairs = 1;

/// At most this many groups carry one pair in the file (the count is one
/// byte); a group beyond it is not remembered for the pair.
const int kGroupsPerPairAtMost = 255;

/// A co-member who is not a contact (§4.3): what the mailbox knows of it.
///
/// ── ONE `s_AB` FROM SEVERAL GROUPS ──────────────────────────────────────
///
/// Every group that makes the two co-members brings its own seed, drawn by
/// its inviter; the two sides may form the pair through DIFFERENT groups
/// (the joins happen in different orders). A pair that kept "the first
/// seed" would then compute two different `K_AB` — and neither code would
/// match. So each group's seed is kept, and the pair's `s_AB` is the seed
/// of the group with the SMALLEST identifier ([pairRandom]): as soon as both
/// sides carry the same groups, they agree, without a message between them.
class GroupPair {
  /// Its address as it signed it on joining — later the newer copy an
  /// envelope of it carried (the adoption rule, [Address.adopt]).
  Address address;

  /// The seed of every group that carries this pair (identifier hex -> the
  /// `s_AB` drawn by that group's inviter, §4.3). Never empty in the store.
  final Map<String, Uint8List> groupSeeds;

  /// Its fixed neighbours: first as the inviter knew them, later as they
  /// ride sealed in its messages (§9.2).
  List<CardAddress> neighbours;

  /// Its public day keys (§8.2), by UTC day.
  Map<int, Uint8List> dayKey;

  /// When the own day keys last went to it — `null`: never.
  DateTime? dayKeySent;

  GroupPair({
    required this.address,
    required Map<String, Uint8List> groupSeeds,
    List<CardAddress> neighbours = const [],
    Map<int, Uint8List>? dayKey,
    this.dayKeySent,
  })  : groupSeeds = {...groupSeeds},
        neighbours = neighbourListClean(neighbours),
        dayKey = dayKey ?? {};

  /// The groups that carry this pair (their identifiers, hex).
  Iterable<String> get groups => groupSeeds.keys;

  /// `s_AB` of the pair: the seed of the smallest group identifier.
  Uint8List get pairRandom =>
      groupSeeds[(groupSeeds.keys.toList()..sort()).first]!;
}

class GroupPairStore {
  final FileEncryption _enc;
  final String _path;

  /// Key: identifier of the co-member (hex).
  final Map<String, GroupPair> pairs = {};

  /// Key: [seedKey] of group and co-member — a waiting `s_AB`.
  final Map<String, Uint8List> seeds = {};

  GroupPairStore._(this._enc, this._path);

  /// The key of a waiting seed.
  static String seedKey(String groupHex, String identifierHex) =>
      '$groupHex:$identifierHex';

  /// Loads the store in [directory], or an empty one if there is none.
  /// Throws [MemoryError] if one lies there that cannot be read.
  static GroupPairStore open(Directory directory, Uint8List key) {
    directory.createSync(recursive: true);
    final s = GroupPairStore.empty(directory, key);
    if (File('${s._path}.enc').existsSync()) {
      final bytes = s._enc.readBinaryFile(s._path);
      if (bytes == null) {
        throw MemoryError('${s._path}.enc exists, but cannot be read');
      }
      s._decode(bytes);
    }
    return s;
  }

  /// An empty store in [directory] — it replaces an unreadable one at the
  /// next [save].
  static GroupPairStore empty(Directory directory, Uint8List key) =>
      GroupPairStore._(FileEncryption(baseDir: directory.path, key: key),
          '${directory.path}/$kFileGroupPairs');

  void save() => _enc.writeBinaryFile(_path, _encode());

  Uint8List _encode() {
    final b = BytesBuilder()..addByte(kVersionGroupPairs);
    b.add(_u16(pairs.length));
    for (final p in pairs.values) {
      addressChainWrite(b, p.address);
      neighbourListWrite(b, neighbourListClean(p.neighbours));
      final days = p.dayKey.keys.toList()..sort();
      final kept = days.length > kDayKeyAtMost
          ? days.sublist(days.length - kDayKeyAtMost)
          : days;
      b.addByte(kept.length);
      for (final t in kept) {
        b
          ..add(_u32(t))
          ..add(p.dayKey[t]!);
      }
      b.add(_u64(p.dayKeySent?.millisecondsSinceEpoch ?? 0));
      final groups = p.groups.take(kGroupsPerPairAtMost).toList();
      b.addByte(groups.length);
      for (final g in groups) {
        _shortWrite(b, _unhex(g));
        b.add(p.groupSeeds[g]!);
      }
    }
    b.add(_u16(seeds.length));
    for (final e in seeds.entries) {
      final cut = e.key.indexOf(':');
      _shortWrite(b, _unhex(e.key.substring(0, cut)));
      b
        ..add(_unhex(e.key.substring(cut + 1)))
        ..add(e.value);
    }
    return b.toBytes();
  }

  void _decode(Uint8List bytes) {
    try {
      final l = Reader(bytes);
      final version = l.byte();
      if (version != kVersionGroupPairs) {
        throw MemoryError('group-pair store: unknown version $version');
      }
      for (var n = l.u16(); n > 0; n--) {
        final address = addressChainRead(l);
        final neighbours = neighbourListRead(l.bytes, 'group-pair neighbours');
        final dayKey = <int, Uint8List>{};
        for (var d = l.byte(); d > 0; d--) {
          dayKey[l.u32()] = l.bytes(32);
        }
        final sent = l.u64();
        final seeds = <String, Uint8List>{};
        for (var g = l.byte(); g > 0; g--) {
          seeds[_hex(l.bytes(l.byte()))] = l.bytes(kPairRandomLength);
        }
        if (seeds.isEmpty) throw MemoryError('group pair without a group');
        pairs[_hex(address.identifier)] = GroupPair(
          address: address,
          groupSeeds: seeds,
          neighbours: neighbours,
          dayKey: dayKey,
          dayKeySent:
              sent == 0 ? null : DateTime.fromMillisecondsSinceEpoch(sent),
        );
      }
      for (var n = l.u16(); n > 0; n--) {
        final group = _hex(l.bytes(l.byte()));
        final identifier = _hex(l.bytes(32));
        seeds[seedKey(group, identifier)] = l.bytes(kPairRandomLength);
      }
      l.done();
    } on MemoryError {
      rethrow;
    } catch (e) {
      throw MemoryError('group-pair store damaged: $e');
    }
  }
}

void _shortWrite(BytesBuilder b, Uint8List v) {
  if (v.isEmpty || v.length > 255) {
    throw ArgumentError('group identifier of ${v.length} B, allowed 1..255');
  }
  b
    ..addByte(v.length)
    ..add(v);
}

String _hex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
Uint8List _unhex(String h) => Uint8List.fromList([
      for (var i = 0; i + 1 < h.length; i += 2)
        int.parse(h.substring(i, i + 2), radix: 16),
    ]);
Uint8List _u16(int v) =>
    (ByteData(2)..setUint16(0, v, Endian.big)).buffer.asUint8List();
Uint8List _u32(int v) =>
    (ByteData(4)..setUint32(0, v, Endian.big)).buffer.asUint8List();
Uint8List _u64(int v) =>
    (ByteData(8)..setUint64(0, v, Endian.big)).buffer.asUint8List();
