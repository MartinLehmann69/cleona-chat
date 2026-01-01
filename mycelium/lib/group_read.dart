import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:mycelium/group.dart';
import 'package:mycelium/envelope.dart';

/// The read side of a group — open and check what comes in.
///
/// It stands in a separate file because `group.dart` would otherwise exceed the
/// line budget. The budget has no exception mechanism: if it does not
/// fit, the design is wrong, not the limit. An extension instead of
/// inheritance, so that there is still ONE group and not two
/// kinds of it.
///
/// Why the cut lies exactly here: [receive] and opening a
/// collected message are the only larger block that `group.dart`
/// itself calls nowhere — it hangs on the network, not on the group. Everything
/// the group does on its own (admit, remove, change role,
/// change keys, send) stays over there. That is why `group.dart` cannot
/// import this file either, and does not have to.
///
/// From over there only the public side is needed: [Group.identifier],
/// [Group.keyFrom], [Group.charsData], [Group.keyCame],
/// [Group.incoming], [Group.onInbound], [Group.me].
extension GroupsRead on Group {
  /// A collected group message (0x60) or a sealed
  /// key delivery (0x61) comes in. Returns the message if
  /// it was one and it is not the own one.
  GroupsInbound? receive(Uint8List packet) {
    if (packet.isEmpty) throw GroupsError('empty packet');
    switch (packet[0]) {
      case kKindGroupsMessage:
        return _messageCame(packet);
      case kKindKeyDelivery:
        keyCame(packet);
        return null;
      default:
        throw GroupsError('unexpected kind ${packet[0]}');
    }
  }

  GroupsInbound? _messageCame(Uint8List packet) {
    const header = 1 + 4 + cryptoSecretBoxNonceBytes;
    if (packet.length <= header + cryptoSecretBoxMacBytes) {
      throw GroupsError('does not open');
    }
    final gen = ByteData.sublistView(packet, 1, 5).getUint32(0, Endian.big);
    final k = keyFrom(gen);
    // From here on every failure is the same sentence: missing key,
    // bent bytes, signature that does not hold — otherwise it would be an oracle.
    if (k == null) throw GroupsError('does not open');
    Uint8List inside;
    try {
      inside = SodiumFFI().secretBoxDecrypt(
          cut(packet, header, packet.length), k, cut(packet, 5, header));
    } catch (_) {
      throw GroupsError('does not open');
    }
    const beforeSig = kGroupsIdentifierLength + Address.length + 2 + 64; // up to sig
    if (inside.length < beforeSig) throw GroupsError('does not open');
    var p = 0;
    final found = cut(inside, p, p += kGroupsIdentifierLength);
    final sender = Address.outBytes(cut(inside, p, p += Address.length));
    final dsaLength = ByteData.sublistView(inside).getUint16(p, Endian.big);
    p += 2;
    final edSig = cut(inside, p, p += 64);
    if (dsaLength > OqsFFI.mlDsaSignatureLength ||
        p + dsaLength > inside.length) {
      throw GroupsError('does not open');
    }
    final dsaSig = cut(inside, p, p += dsaLength);
    final textBytes = cut(inside, p, inside.length);
    if (!byteEqual(found, identifier)) throw GroupsError('does not open');
    final signed = charsData(gen, sender, textBytes);
    final sodium = SodiumFFI();
    final oqs = OqsFFI()..init();
    if (!sodium.verifyEd25519(signed, edSig, sender.ed25519Pk) ||
        !oqs.mlDsaVerify(signed, dsaSig, sender.mlDsaPk)) {
      throw GroupsError('does not open');
    }
    // The own message already lies in [sent]: the sender is not a
    // recipient of itself, even if it passes by the deposit.
    if (sender.sameIdentity(me.address)) return null;
    final inbound = GroupsInbound(
        groupsIdentifier: found, generation: gen, from: sender,
        text: utf8.decode(textBytes), at: DateTime.now());
    incoming.add(inbound);
    onInbound?.call(inbound);
    return inbound;
  }
}
