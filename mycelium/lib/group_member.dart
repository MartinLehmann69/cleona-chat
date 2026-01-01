/// A group member's entry as the member itself signed it on joining
/// (V4.2 §16.2.2 "Invites", owner decision B-3, E3 = yes).
///
/// The invitation carries, for every member, its address — all four public
/// keys, key state, rotation chain where there is one — and the inviter
/// passes it on. Without the member's own signature the inviter could put
/// other KEM keys into the list and read the first legs of a group pair
/// (proposal B-3 §3, "Sicherheit (2)"). With it, the list proves what the
/// member said about itself, and the inviter can only withhold an entry,
/// not change one.
///
/// The signature covers a domain tag, the group and the address with its
/// chain, under BOTH signing keys of that address (Ed25519 and ML-DSA-65, as
/// every envelope, §4.4). It binds the entry to ONE group: an entry signed
/// for another group is not an entry of this one.
///
/// ```
/// signed = "cleona-group-member/v1" ‖ group length (1 B) ‖ group
///        ‖ address (Address.length) ‖ its chain (RotationChain wire)
/// ```
///
/// The fixed neighbours travel next to the entry and are not signed: they
/// are hints "as the inviter knows them" (§16.2.2), and a wrong hint costs a
/// `0x21`, never a key (§15.2).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/identity/rotation_chain.dart';
import 'package:mycelium/card_address.dart';
import 'package:mycelium/envelope.dart' show Address, PostBox;
import 'package:mycelium/memory_invitation.dart' show Reader;
import 'package:mycelium/neighbour_list.dart';

final Uint8List _domain = utf8.encode('cleona-group-member/v1');

/// The address with its rotation chain, as it travels in a member entry.
Uint8List groupMemberAddressWire(Address a) =>
    (BytesBuilder()
          ..add(a.toBytes())
          ..add(a.chain.toWire()))
        .toBytes();

/// What the member signs for [group].
Uint8List groupMemberSigned(Uint8List group, Uint8List addressWire) {
  if (group.isEmpty || group.length > 255) {
    throw ArgumentError('group identifier of ${group.length} B');
  }
  return (BytesBuilder()
        ..add(_domain)
        ..addByte(group.length)
        ..add(group)
        ..add(addressWire))
      .toBytes();
}

/// The own entry for [group], signed with the CURRENT keys of [me] — at the
/// explicit join (§16.2.2).
({Uint8List address, Uint8List ed, Uint8List dsa}) groupMemberSign(
    PostBox me, Uint8List group) {
  final wire = groupMemberAddressWire(me.address);
  final sig = me.sign(groupMemberSigned(group, wire));
  return (address: wire, ed: sig.ed, dsa: sig.dsa);
}

/// Checks an entry for [group] and returns its address — or `null` if the
/// address is malformed, its keys do not found its identifier without a
/// chain that holds (§4.5.4), or either signature does not verify under the
/// address's own keys. Never throws.
Address? groupMemberCheck(
    Uint8List group, Uint8List addressWire, Uint8List ed, Uint8List dsa) {
  try {
    if (addressWire.length < Address.length + 1) return null;
    final raw = Uint8List.sublistView(addressWire, 0, Address.length);
    final keys = ChainKeys(Uint8List.sublistView(raw, 32, 64),
        Uint8List.sublistView(raw, 64, 64 + OqsFFI.mlDsaPublicKeyLength));
    final n = RotationChain.wireLengthAt(addressWire, Address.length);
    if (Address.length + n != addressWire.length) return null;
    final chain = RotationChain.fromWire(
        Uint8List.fromList(Uint8List.sublistView(addressWire, Address.length)),
        keys);
    // Not `proven`: a rotated address passes only with a chain that holds.
    final a = Address.outBytes(Uint8List.fromList(raw), chain: chain);
    final signed = groupMemberSigned(group, addressWire);
    if (!SodiumFFI().verifyEd25519(signed, ed, a.ed25519Pk)) return null;
    if (!(OqsFFI()..init()).mlDsaVerify(signed, dsa, a.mlDsaPk)) return null;
    return a;
  } on Object {
    return null;
  }
}

/// Fixed neighbours as they travel next to a member entry (the list codec
/// of `neighbour_list.dart`, count 0..3).
Uint8List groupMemberNeighboursWire(List<CardAddress> list) {
  final b = BytesBuilder();
  neighbourListWrite(b, neighbourListClean(list));
  return b.toBytes();
}

/// Counterpart to [groupMemberNeighboursWire]; an empty or broken list is
/// no list — the hint is dropped, the entry is not.
List<CardAddress> groupMemberNeighboursRead(Uint8List wire) {
  if (wire.isEmpty) return const [];
  try {
    final l = Reader(wire);
    final list = neighbourListRead(l.bytes, 'member neighbours');
    l.done();
    return list;
  } on Object {
    return const [];
  }
}
