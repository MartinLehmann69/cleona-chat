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
/// ── A HOP THAT DOES NOT ANSWER IS NO POSSIBLE HOP (S405) ────────────────
///
/// §8.1 takes the last resort where "the only POSSIBLE first hop" is a named
/// node. Until S405 an open neighbour counted as possible whether or not it
/// answered: the phone of 05.10.2026 sent its request, and every message,
/// to dead addresses while the one live node — the bootstrap, named by the
/// card — was never tried (`berichte/S405-VORLAGE-RUECKSCHRITT-ERSTKONTAKT.md`;
/// it worked on 24.09. before 122b8264). Owner decision 06.10.2026, variant
/// B: the plan lists every possible hop in order ([StepThreePlan.later]) and
/// the shared node as [StepThreePlan.resort]; when the shell reports that a
/// hop did not answer (`Shell.onSilent`), `code_send_retry.dart` hands the
/// same sending to the next, after the last to the shared node directly.
/// Cost: at most 1.6 s per silent candidate (two answer deadlines), at most
/// [kOpenSetAtMost] − 1 of them. A live link is tried first (OP-23).
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
/// [hop]. [why] is for the report. [later]: the further possible hops in
/// order, tried when [hop] does not answer; [resort]: the shared node the
/// recipient named, which gets the inner `0x20` directly when none of them
/// answers (`null` if there is none, or [hop] is already the last resort).
typedef StepThreePlan = ({
  CardAddress? hop,
  List<CardAddress> next,
  String why,
  List<CardAddress> later,
  CardAddress? resort,
});

/// The open set with the neighbours whose link is live first (OP-23, S398):
/// a silent intermediary loses step 3 until the requester collects at its
/// next edge (lab E/O2, T2: 25.9 s). The draw (§5.2) stays the order within
/// each group; without a live neighbour nothing changes. [live]:
/// `Node.linkLive` — a key heard within the link silence (`Shell.stands`).
List<Neighbour> liveFirst(List<Neighbour> open, bool Function(Neighbour) live) =>
    [...open.where(live), ...open.where((n) => !live(n))];

/// Why the open neighbour [o] cannot be the first hop of step 3, or `null`
/// if it can: it holds a seat, is a contact's device, or the recipient
/// named it (no node may be both hops). [reach]: its address this node can
/// send to.
String? _openBar(Neighbour o, CardAddress? reach, List<CardAddress> named,
        bool Function(Neighbour n) contact) =>
    reach == null
        ? 'no socket'
        : o.seated
            ? 'seated'
            : contact(o)
                ? 'contact'
                : named.any(o.knows)
                    ? 'named'
                    : null;

/// At most this many candidates are listed in the step-3 report.
const int _kNoteMax = 8;

/// Diagnosis for the `Step 3:` report (S398 lab run 2, finding 2: Alice →
/// Carol took 2 min 7 s via a dead intermediary, and the log could not say
/// whether a live one existed): the open set in the order step 3 tried it,
/// each with its live marker and, if it cannot be the hop, why. Log only.
String _openNote(List<Neighbour> open, bool Function(Neighbour n) live,
    CardAddress? Function(Neighbour n) reach, List<CardAddress> named,
    bool Function(Neighbour n) contact) {
  final shown = [
    for (final o in open.take(_kNoteMax))
      '${reach(o) ?? o.sendAddress} ${live(o) ? "live" : "silent"}'
          '${switch (_openBar(o, reach(o), named, contact)) {
        null => '',
        final b => ' $b',
      }}',
  ];
  final more = open.length > _kNoteMax ? ', …' : '';
  return '; open set ${open.where(live).length} of ${open.length} live'
      '${shown.isEmpty ? '' : ': ${shown.join(', ')}$more'}';
}

/// See the file header. [fixed]: the own fixed neighbours in order
/// (`Neighbourhood.fixedNeighbours`); [open]: the open set; [recipient]: the
/// recipient's fixed neighbours; [contact]: is a neighbour a contact's
/// device; [speaks]: has this node a socket for the address's family.
/// [live]: `Node.linkLive` — given, the open set is taken live first
/// ([liveFirst], OP-23) and the report of an open hop or the last resort
/// names the open set with its live markers (S398 lab run 2, finding 2).
/// `null`: no next address, or none this node could send to.
StepThreePlan? stepThreePlan({
  required List<Neighbour> fixed,
  required List<Neighbour> open,
  required List<CardAddress> recipient,
  required bool Function(Neighbour n) contact,
  required bool Function(CardAddress a) speaks,
  bool Function(Neighbour n)? live,
}) {
  final named = neighbourListClean(recipient);
  if (named.isEmpty) return null;
  if (live != null) open = liveFirst(open, live);
  if (fixed.isEmpty) {
    final direct = [for (final a in named) if (speaks(a)) a];
    return direct.isEmpty
        ? null
        : (
            hop: null,
            next: direct,
            why: '0x20 direct (no own fixed neighbour)',
            later: const <CardAddress>[],
            resort: null,
          );
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
  // The shared node, sent to directly — the last resort (§8.1): the first
  // own fixed neighbour the recipient named.
  //
  // The ADDRESS is the one the recipient named (for a first contact: the
  // card's), not the first one remembered for that neighbour. Field test
  // 06.10.2026: the phone (LTE, WLAN off) remembered the bootstrap first
  // under its old private LAN address and sent the last resort there —
  // nothing arrived. Up to 9a1bced5 the 0x20 went to the card's address.
  CardAddress? resort;
  for (final f in fixed) {
    if (clear(f)) continue;
    for (final a in named) {
      if (f.knows(a) && speaks(a)) {
        resort ??= a;
      }
    }
    resort ??= reach(f);
  }
  final viaFixed = [
    for (final f in fixed)
      if (clear(f) && reach(f) != null) reach(f)!,
  ];
  final viaOpen = [
    for (final o in open)
      if (_openBar(o, reach(o), named, contact) == null) reach(o)!,
  ];
  final hops = [...viaFixed, ...viaOpen];
  if (hops.isNotEmpty) {
    final note = viaFixed.isNotEmpty || live == null
        ? ''
        : _openNote(open, live, reach, named, contact);
    return (
      hop: hops.first,
      next: next,
      why: viaFixed.isNotEmpty
          ? '0x22 via the own fixed neighbour'
          : '0x22 via an open non-contact neighbour (every own fixed neighbour '
              'is one the recipient named$note)',
      later: hops.skip(1).toList(),
      resort: resort,
    );
  }
  if (resort != null) {
    final note =
        live == null ? '' : _openNote(open, live, reach, named, contact);
    return (
      hop: null,
      next: [resort],
      why: '0x20 to the own fixed neighbour, which the recipient named too — '
          'LAST RESORT, that node sees both ends (no other hop$note)',
      later: const <CardAddress>[],
      resort: null,
    );
  }
  return null;
}
