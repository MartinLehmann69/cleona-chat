import 'dart:math' as math;

import 'package:mycelium/neighbourhood.dart';

/// Size of the open set (V4.2 §5.2: "The draw picks from an open set
/// of four").
const int kOpenSet = 4;

/// The open set: the four neighbours among which the cover stream's clock
/// chooses (§5.2). At `R_cover` each thus gets a packet about every 32 s —
/// within the two minutes that RFC 4787 prescribes to an address translation as
/// minimum lifetime. The other neighbours are known
/// addresses, not open paths.
///
/// ── FIXED SEATS FIRST, THE REST LOOSE (W7, S391; contact seats 2026-09) ─
///
/// The card's seat holds the neighbour that the own cards name
/// ([Neighbour.fixed]) — only via it is a node behind NAT reachable for the
/// reader of its card, so exactly this path must stay open. Up to three
/// contact seats ([Neighbour.contactSeat], `neighbourhood_contacts.dart`)
/// hold devices of own contacts; the four seats are the card's and up to
/// three contacts, and seats no contact holds are loose.
/// The fixed seats stand in the list, not here: this class only remembers
/// the loose seats, by [Neighbour.id] — a neighbour is a node, its
/// addresses and their order can change (S394 V4).
///
/// Drawing happens at the edges from §11.8 (start, network change, new
/// neighbour, removal) — never on a clock. Confirmed neighbours
/// (stamp younger than [Neighbourhood.staleAfter]) take precedence: cover
/// should go to addresses the node deals with anyway (§5.2),
/// not to a mere hint from foreign hands. If there are too few,
/// the others fill up — otherwise a freshly started node
/// that knows only hints would open no path at all.
class OpenSet {
  final math.Random _random;
  List<int> _loose = const [];

  OpenSet(this._random);

  /// The seated ones first (card's seat, then the contact seats, in the
  /// order of [list]), then the loose ones that still stand in [list] —
  /// at most [kOpenSet]. A loose seat whose neighbour is gone
  /// stays empty until the next edge (the removal IS one and draws
  /// anew).
  List<Neighbour> read(List<Neighbour> list) {
    final afterKey = {for (final n in list) n.id: n};
    return [
      ...list.where((n) => n.seated),
      for (final s in _loose)
        if (afterKey[s] case final n? when !n.seated) n,
    ].take(kOpenSet).toList();
  }

  /// Redraws the loose seats from [list].
  void draw(List<Neighbour> list, DateTime now, [math.Random? random]) {
    final z = random ?? _random;
    final fresh = <Neighbour>[];
    final rest = <Neighbour>[];
    for (final n in list) {
      if (n.seated) continue;
      final young = now.difference(n.last) < Neighbourhood.staleAfter;
      (young ? fresh : rest).add(n);
    }
    fresh.shuffle(z);
    rest.shuffle(z);
    final places = kOpenSet - list.where((n) => n.seated).length;
    _loose = [
      for (final n in [...fresh, ...rest].take(places)) n.id
    ];
  }
}
