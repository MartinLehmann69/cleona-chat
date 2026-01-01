/// The pairs of contacts restored from the rescue bundle that wait for their
/// first envelope (V4.2 §13.2.1, §13.3.2; D-70, owner 21.10.2026) — the
/// mailbox side of what the application took over.
///
/// ── WHY THE MAILBOX NEEDS THEM BEFORE THE FIRST ENVELOPE ─────────────────
///
/// The bundle names per contact its founding Ed25519 key and `s_AB` — "forming
/// `K_AB` and the codes (§4.3)" — but no full address (E4): the contact's
/// current keys come only with its first envelope, which anchors it (E7-b,
/// application). Until S407-R the mailbox formed nothing for such a contact:
/// no inbound code, so the recovering device registered none and did not
/// recognise a `0x20` or `0x23` under one (S407-VB20, "Erreichbarkeit nach
/// Wiederherstellung": "day keys to 0 contact(s)", Bob's `0x23` handed on).
/// §13.2.1 since `44bdea4c`: "At the takeover the recovering device forms
/// `K_AB` and the codes of every restored contact from the bundle … a
/// contact's packet under its code then reaches the recovering device as
/// after a move (§11.8.9), and a `0x23` under such a code is its own."
///
/// The application holds the waiting pairs (they are conversation metadata,
/// §21.4.2) and hands them here read live ([recoveryPairs]); an anchored
/// contact leaves them and stands in the mailbox as a contact.
library;

import 'dart:typed_data';

import 'package:mycelium/card_address.dart';
import 'package:mycelium/envelope.dart' show Address;
import 'package:mycelium/mailbox.dart';
import 'package:mycelium/mailbox_group_pair.dart' show MailboxGroupPair;
import 'package:mycelium/mailbox_pair.dart' show suchContentOpen;
import 'package:mycelium/pair.dart' show foundingPk, pairCode, pairSecretWith;

/// A contact restored from the rescue bundle that waits for its first
/// envelope (§13.2.1, E7-b): the `s_AB` and the founding Ed25519 key the
/// bundle names.
typedef RecoveryPair = ({Uint8List sAB, Uint8List foundingPk});

final Expando<Map<String, RecoveryPair> Function()> _pairs =
    Expando('restored pairs waiting for their anchor');

extension MailboxRecoveryPairs on Mailbox {
  /// The application's restored contacts that wait for their anchor, by
  /// identifier (hex). Read live at every use, no second copy here.
  set recoveryPairs(Map<String, RecoveryPair> Function() all) =>
      _pairs[this] = all;

  /// The waiting pairs — none that is a contact or a group pair of this
  /// mailbox already: those form `K_AB` and their codes on their own.
  Map<String, RecoveryPair> get recoveryPairsWaiting => {
        for (final e in (_pairs[this]?.call() ?? const {}).entries)
          if (contactOrNull(e.key) == null && groupPairOrNull(e.key) == null)
            e.key: e.value,
      };

  /// The waiting restored pair with [identifier] (hex), or `null`.
  RecoveryPair? recoveryPairOf(String identifier) =>
      contactOrNull(identifier) != null ? null : _pairs[this]?.call()[identifier];

  /// `K_AB` of a waiting pair — the formula of an anchored contact (§4.3).
  Uint8List recoveryKey(RecoveryPair p) =>
      pairSecretWith(identity.postBox, p.foundingPk, p.sAB);

  /// The codes contact → this identity on UTC day [day] of every waiting
  /// pair (§8.1): registered and recognised like a contact's.
  List<Uint8List> recoveryInboundCodes(int day) => [
        for (final p in recoveryPairsWaiting.values)
          pairCode(recoveryKey(p),
              fromPk: p.foundingPk,
              toPk: foundingPk(identity.postBox.address),
              day: day),
      ];

  /// The application keeps a waiting contact's fixed neighbours as they
  /// come — in a `0x23` (§8.1) or with its first envelope (§9.2) — in place
  /// of the bundle's: the anchor then hands the mailbox the current ones.
  set recoveryNeighbours(
          void Function(String identifier, List<CardAddress> list) heard) =>
      _heard[this] = heard;

  /// A `0x23` under [code] from a waiting pair (§8.1, §13.2.1: "a `0x23`
  /// under such a code is its own") — the counterpart of
  /// [MailboxPair.whereAreYouAccept] for a contact. Days as there, around
  /// [today]. Returns the sender's fixed neighbours if its seal opens under
  /// the bundle's `K_AB`, else `null`.
  ///
  /// ANSWERED AS FAR AS E4 ALLOWS: the bundle carries no full address of the
  /// contact, so nothing can be sealed to it before its first envelope. The
  /// answer "on the ordinary way" (§8.1) is the registration anew that the
  /// caller starts ([CodeRoute.newRegister]); the contact's next sending
  /// reaches this device, anchors it, and its acknowledgement carries the
  /// own fixed neighbours (§9.2).
  List<CardAddress>? recoveryWhereAreYou(
      Uint8List code, Uint8List content, int today) {
    final me = foundingPk(identity.postBox.address);
    for (final MapEntry(key: id, value: p) in recoveryPairsWaiting.entries) {
      final kAB = recoveryKey(p);
      for (var day = today - 1; day <= today + 1; day++) {
        final c = pairCode(kAB, fromPk: p.foundingPk, toPk: me, day: day);
        if (!_same(c, code)) continue;
        final n = suchContentOpen(kAB, content)?.list;
        report?.call('0x23 from restored ${id.substring(0, 8)} (no anchor '
            'yet): ${n == null ? "seal does not open — discarded" : "${n.length} fixed neighbour(s); answered by registering anew (no address before its first envelope, E4)"}');
        if (n != null) _heard[this]?.call(id, n);
        return n;
      }
    }
    return null;
  }

  /// A waiting pair's fixed neighbours rode in its envelope (§9.2) — they
  /// come before the envelope anchors it, so there is no contact to keep
  /// them for yet. `true` if handed to the application.
  bool recoveryNeighboursHeard(Address from, List<CardAddress> list) {
    final id = identifierFrom(from);
    if (list.isEmpty || recoveryPairOf(id) == null) return false;
    _heard[this]?.call(id, list);
    return true;
  }
}

final Expando<void Function(String identifier, List<CardAddress> list)> _heard =
    Expando('fixed neighbours of restored pairs');

bool _same(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  var d = 0;
  for (var i = 0; i < a.length; i++) {
    d |= a[i] ^ b[i];
  }
  return d == 0;
}
