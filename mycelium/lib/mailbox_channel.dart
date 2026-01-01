/// The nudge of a group or channel on the shared key (V4.2 §16.2.5 step 3),
/// as the identity of this mailbox sends and opens it.
///
/// The same encrypted post, without the entries of its inline objects, goes
/// to every member that has shown the capability as one `0x68`, wrapped per
/// pair so that a forwarder serving two members never sees the same bytes
/// twice, over ladder steps 1 and 3 (§7.1, §8.1) and never into a post box.
/// It is not acknowledged (§9.2) and not sent again (§9.3): a nudge that
/// does not arrive is not a failure — the member collects the post.
///
/// ```
/// 0x68 | code(A→B, today) 16 | wrap 16 | AES-256-GCM(entry)
/// key = HKDF(K_AB, "channel/nudge" ‖ wrap)
/// ```
///
/// The code names the pair to the recipient the way handing on by code does
/// (§8.1): it changes every day and names neither side. The 16 random wrap
/// bytes make the key one per nudge.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:mycelium/address_class.dart' show routesToContact;
import 'package:mycelium/card_address.dart';
import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/ladder.dart' show Target;
import 'package:mycelium/mailbox.dart';
import 'package:mycelium/mailbox_group_pair.dart';
import 'package:mycelium/pair.dart';

final SodiumFFI _na = SodiumFFI();
const int _kWrapLength = 16;

/// What a nudge adds to its entry: kind, code, wrap and the AEAD tag.
const int kNudgeOverhead = 1 + kCodeLength + _kWrapLength + 16;
final Uint8List _kZeroNonce = Uint8List(12);

Uint8List _nudgeKey(Uint8List kAB, Uint8List wrap) => _na.hkdfSha256(kAB,
    info: Uint8List.fromList([...utf8.encode('channel/nudge'), ...wrap]),
    length: 32);

extension MailboxChannel on Mailbox {
  /// Sends [entry] to the member [memberHex] (contact or group pair) as a
  /// nudge. `false` when this identity forms no `K_AB` with it — then the
  /// member collects.
  bool nudgeSend(String memberHex, Uint8List entry, {DateTime? now}) {
    final k = contactOrNull(memberHex);
    final p = k == null ? groupPairOrNull(memberHex) : null;
    final address = k?.address ?? p?.address;
    final s = k?.pairRandom ?? p?.pairRandom;
    if (address == null || s == null || address.foundingEd25519Pk == null) {
      return false;
    }
    final me = identity.postBox;
    final kAB = pairSecret(me, address, s);
    final code = pairCode(kAB,
        fromPk: foundingPk(me.address),
        toPk: foundingPk(address),
        day: utcDay(now ?? DateTime.now()));
    final wrap = _na.randomBytes(_kWrapLength);
    final packet = Uint8List.fromList([
      kinds.kChannelNudge, ...code, ...wrap,
      ..._na.aesGcmEncrypt(entry, _nudgeKey(kAB, wrap), _kZeroNonce),
    ]);
    // Steps 1 and 3 only (§16.2.5 step 3): no post box, no search call.
    final routes = k == null ? null : routesToContact(k);
    node.ladder.send(
        packet,
        Target.outDueTo(routes,
            lan: k?.lastSeen,
            neighbours: k?.neighbours ?? p!.neighbours,
            code: code,
            postBoxApplicable: false));
    return true;
  }

  /// The contacts (identifiers, hex) whose fixed neighbour this node is: a
  /// device registered its codes here (§8.1) from the contact's last
  /// observed address or an address of its card. They receive the
  /// capability notice once (§16.2.5 "Mixed operation within 4.2").
  List<String> servedContacts() {
    final at = node.codeRoute.table.registeredAt.toList();
    bool registered(CardAddress c) => at.any((r) =>
        r.$2 == c.port && _equal(r.$1.rawAddress, c.address));
    return [
      for (final k in contacts)
        if ([if (k.lastSeen case final s?) s, ...k.cardsAddresses].any(registered))
          identifierFrom(k.address),
    ];
  }

  /// Opens a nudge for this identity: the sender's identifier (hex) and the
  /// entry, or `null` when no pair of this identity sends under its code.
  (String, Uint8List)? nudgeOpen(Uint8List packet, {DateTime? now}) {
    if (packet.length <= kNudgeOverhead ||
        packet[0] != kinds.kChannelNudge) {
      return null;
    }
    final code = Uint8List.sublistView(packet, 1, 1 + kCodeLength);
    final wrap =
        Uint8List.sublistView(packet, 1 + kCodeLength, 1 + kCodeLength + _kWrapLength);
    final box = Uint8List.sublistView(packet, 1 + kCodeLength + _kWrapLength);
    final me = identity.postBox;
    final today = utcDay(now ?? DateTime.now());
    for (final k in pairPartners) {
      final kAB = pairSecret(me, k.address, k.s);
      for (var day = today - 1; day <= today + 1; day++) {
        final c = pairCode(kAB,
            fromPk: foundingPk(k.address), toPk: foundingPk(me.address), day: day);
        if (!_equal(c, code)) continue;
        try {
          return (
            identifierFrom(k.address),
            _na.aesGcmDecrypt(box, _nudgeKey(kAB, wrap), _kZeroNonce),
          );
        } on Object {
          return null; // its code, but the seal does not open
        }
      }
    }
    return null;
  }
}

bool _equal(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var d = 0;
  for (var i = 0; i < a.length; i++) {
    d |= a[i] ^ b[i];
  }
  return d == 0;
}
