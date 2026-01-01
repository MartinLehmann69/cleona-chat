/// Where the sender of step 3 sends (V4.2 §8.1; proposal "contacts as fixed
/// neighbours", version 3, rules 7 and 8, 6.2 "Sender behaviour").
///
/// The sender builds ONE `0x20` — the same for every fixed neighbour of the
/// recipient, since each holds the same codes — wraps it into ONE `0x22`
/// naming up to three next addresses (the recipient's fixed neighbours as
/// the recipient last told them, §9.2; for a first contact the card's
/// neighbour, §15.2) and sends that to its OWN fixed neighbour, which hands
/// the inner packet to each of them (`forward_detour.dart`).
///
/// ── NO NODE MAY BE BOTH HOPS ────────────────────────────────────────────
///
/// The first hop is never a node the recipient named: such a node holds the
/// recipient's codes (§8.1), takes the inner packet itself
/// (`Forwarder._heldHere`) and would see both ends. So the first hop is
///
///  1. the first own fixed neighbour the recipient did not name, else
///  2. an open neighbour that is not a contact's device and not named, else
///  3. — **last resort, named** — the shared node itself, the inner `0x20`
///     sent to it directly (the behaviour before this change). Delivery
///     works alone (§3.1): a node whose only neighbour is also the
///     recipient's would otherwise lose step 3, and with one neighbour the
///     post box cannot place either (two acknowledgements, §8.2). The
///     report says so each time.
///
/// Of the next addresses, one that is an own fixed neighbour is left out
/// (6.2: "a next address that is the sender's own fixed neighbour is left
/// out") — unless that leaves none; then the list stays, since the first hop
/// is none of them.
///
/// A sender without a fixed neighbour sends the `0x20` directly to each next
/// address in an own address family (§8.1, §11.1 V1).
///
/// Pure function over lists; `node_codes.dart` applies it. A separate file
/// because `node_codes.dart` stands at the line budget.
library;

import 'package:mycelium/card_address.dart';
import 'package:mycelium/neighbour.dart';
import 'package:mycelium/neighbour_list.dart';

/// The plan for one sending on step 3. [hop] `null`: the `0x20` goes
/// directly to each of [next]; otherwise one `0x22` naming [next] goes to
/// [hop]. [why] is for the report.
typedef StepThreePlan = ({CardAddress? hop, List<CardAddress> next, String why});

/// See the file header. [fixed]: the own fixed neighbours in order
/// (`Neighbourhood.fixedNeighbours`); [open]: the open set; [recipient]: the
/// recipient's fixed neighbours; [contact]: is a neighbour a contact's
/// device; [speaks]: has this node a socket for the address's family.
/// `null`: no next address, or none this node could send to.
StepThreePlan? stepThreePlan({
  required List<Neighbour> fixed,
  required List<Neighbour> open,
  required List<CardAddress> recipient,
  required bool Function(Neighbour n) contact,
  required bool Function(CardAddress a) speaks,
}) {
  final named = neighbourListClean(recipient);
  if (named.isEmpty) return null;
  if (fixed.isEmpty) {
    final direct = [for (final a in named) if (speaks(a)) a];
    return direct.isEmpty
        ? null
        : (hop: null, next: direct, why: '0x20 direct (no own fixed neighbour)');
  }
  bool clear(Neighbour n) => !named.any(n.knows);
  CardAddress? reach(Neighbour n) {
    for (final a in n.addresses) {
      final c = a.asCardAddress;
      if (speaks(c)) return c;
    }
    return null;
  }

  final ownLeftOut = [
    for (final a in named)
      if (!fixed.any((f) => f.knows(a))) a,
  ];
  final next = ownLeftOut.isEmpty ? named : ownLeftOut;
  for (final f in fixed) {
    final to = reach(f);
    if (to != null && clear(f)) {
      return (hop: to, next: next, why: '0x22 via the own fixed neighbour');
    }
  }
  for (final o in open) {
    final to = reach(o);
    if (to == null || o.seated || contact(o) || !clear(o)) continue;
    return (
      hop: to,
      next: next,
      why: '0x22 via an open non-contact neighbour (every own fixed neighbour '
          'is one the recipient named)',
    );
  }
  for (final f in fixed) {
    final to = reach(f);
    if (to == null) continue;
    return (
      hop: null,
      next: [to],
      why: '0x20 to the own fixed neighbour, which the recipient named too — '
          'LAST RESORT, that node sees both ends (no other hop)',
    );
  }
  return null;
}
