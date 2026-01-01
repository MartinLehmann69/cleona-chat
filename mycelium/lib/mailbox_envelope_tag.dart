/// Which pair gets the tagged envelope (V4.2 §4.4.3, §1.2 principle 8;
/// owner 15.10.2026, S407-UMSCHLAG) — the mailbox side of
/// `envelope_tag.dart`.
///
/// `K_AB` comes from [MailboxPair.pairFrom]: a contact with `s_AB`, or a
/// group pair with the `s_AB` its inviter drew (§4.3) — the same secret the
/// codes hang on. Received tags of a group pair are checked under every seed
/// it may arrive under, as its codes are (S407 B-12, [MailboxGroupPair.groupPairInboundKeys]). The tagged form goes only to a pair that SHOWED it reads
/// it; a 4.2.3 device discards it (`envelope_tag.dart`):
///
///  * a contact: [Contact.readsKeys] — the mark of this release's reader,
///    shown by the contact itself (a keyed neighbour list, the suffix behind
///    its invitation line, the bit of a device of it, `neighbour_keys.dart`),
///    and set by a tagged envelope from it ([NeighbourKeysContact.readsKeysShown]);
///  * a group pair: a tagged envelope from it, or the mark its own member
///    entry carries (§16.2.2, [groupPairReadsTag]) — in memory only: the
///    group-pair store keeps its format (a new version would be removed by
///    the enforcer, and with it every pair); after a start the mark comes
///    back with the member state and with the pair's first tagged leg.
///
/// Until then the pair gets the signed form, which every 4.2 device reads.
library;

import 'dart:typed_data';

import 'package:mycelium/envelope.dart' show Address;
import 'package:mycelium/envelope_tag.dart';
import 'package:mycelium/mailbox.dart';
import 'package:mycelium/mailbox_group_pair.dart';
import 'package:mycelium/mailbox_pair.dart';
import 'package:mycelium/mailbox_recovery_pairs.dart';
import 'package:mycelium/neighbour_keys.dart';
import 'package:mycelium/pair.dart' show pairSecret;

final Expando<Set<String>> _groupPairTag = Expando('group pairs reading tags');

bool _sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  var d = 0;
  for (var i = 0; i < a.length; i++) {
    d |= a[i] ^ b[i];
  }
  return d == 0;
}

extension MailboxEnvelopeTag on Mailbox {
  /// Wires the pairs of this identity to its post box — when the mailbox
  /// opens ([MailboxGroupPair.groupPairOpen]).
  void envelopeTagWire() => envelopePairsWire(identity.postBox, _Pairs(this));

  /// The group pair with [identifier] (hex) reads the tagged form — its
  /// member entry says so (§16.2.2) or a tagged leg from it held.
  void groupPairReadsTag(String identifier) =>
      (_groupPairTag[this] ??= {}).add(identifier);

  /// Whether [to] showed it reads the tagged form.
  bool readsTag(Address to) {
    final id = identifierFrom(to);
    if (contactOrNull(id) != null) return readsKeysOf(to);
    return groupPairOrNull(id) != null &&
        (_groupPairTag[this]?.contains(id) ?? false);
  }
}

class _Pairs implements EnvelopePairs {
  final Mailbox m;
  _Pairs(this.m);

  @override
  Uint8List? tagKeyTo(Address to) =>
      m.readsTag(to) ? m.pairFrom(to)?.kAB : null;

  @override
  List<Uint8List> tagKeysOf(Address from) {
    final id = identifierFrom(from);
    if (m.contactOrNull(id) != null) {
      return [if (m.pairFrom(from)?.kAB case final k?) k];
    }
    final waiting = m.recoveryPairOf(id);
    if (waiting != null) return _recoveryKeys(from, waiting);
    return m.groupPairInboundKeys(id); // every seed it may arrive under (B-12)
  }

  /// `K_AB` of a restored contact that waits for its anchor (§13.2.1,
  /// `mailbox_recovery_pairs.dart`): a tagged envelope from one is checked
  /// under the `K_AB` of the bundle's pair (§4.4.3 "the K_AB of the pair the
  /// sender address names") — the same [pairSecret] as for an anchored
  /// contact, both FOUNDING keys and the `s_AB` of the bundle. Only when the
  /// envelope's founding key is the one the bundle names; otherwise no key,
  /// and the tag is refused.
  List<Uint8List> _recoveryKeys(Address from, RecoveryPair waiting) {
    final founding = from.foundingEd25519Pk;
    if (founding == null || !_sameBytes(founding, waiting.foundingPk)) {
      return const [];
    }
    return [pairSecret(m.identity.postBox, from, waiting.sAB)];
  }

  @override
  void tagShown(Address from) {
    final id = identifierFrom(from);
    if (m.contactOrNull(id) != null) {
      m.readsKeysShown(from);
    } else if (m.groupPairOrNull(id) != null && !m.readsTag(from)) {
      m.groupPairReadsTag(id);
      m.report?.call('group pair ${id.substring(0, 8)} reads tagged envelopes');
    }
  }
}
