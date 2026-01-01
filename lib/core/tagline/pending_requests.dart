import 'dart:convert';
import 'dart:typed_data';

/// Remembers over which partner a request came in.
///
/// WHAT FOR. A harvest request runs over several hops to the responsible
/// relay (§11.2). The answer must find its way back without the relay
/// learning WHO asked. Every hop remembers „this identifier came from
/// this partner" and sends the answer back the same way. No
/// node thereby knows more than its two neighbours — the same
/// property the outward path has too.
///
/// WHY WITH PERIOD AND CAP. The state lies with every hop, and it
/// arises at someone else's instigation. Without a period it would stay put if
/// no answer comes; without a cap a neighbour could create any amount
/// of it. Both are attacks that cost nothing — so they cost
/// nothing here either.
///
/// NO CLOCK IN THE MODULE. The time is handed in, as everywhere in
/// this layer: that way expiry can be checked without waiting.
final class PendingRequests {
  /// Maximum number of simultaneously open requests.
  final int capacity;

  /// How long an identifier is remembered.
  ///
  /// Long enough for a few hops and the answer, short enough that
  /// leftover state disappears by itself.
  final Duration lifetime;

  /// How many return paths ONE partner may occupy at most.
  ///
  /// ── WHY THE GLOBAL CAP IS NOT ENOUGH (S357, counter-reading) ──────
  ///
  /// The state arises at SOMEONE ELSE'S instigation, and the incoming
  /// path is not throttled: `CellTransport.emitControl` sends out
  /// immediately, and the receiving side hangs on `channel.inbound.listen` —
  /// the cover cycle only limits what a node sends BY ITSELF.
  /// A single neighbour can therefore send frames as fast as
  /// UDP carries, and with a purely global cap it occupies the whole
  /// budget.
  ///
  /// That would not merely be ugly: harvest and search tie their
  /// FORWARDING to a free slot (`… && pending.remember(...)`, otherwise
  /// „harvest ends here"). A filled-up pot thus makes the node
  /// stop relaying for others — one neighbour would have switched off
  /// the relay function of the node for all others.
  final int perPartner;

  final Map<String, ({int partner, DateTime seen})> _open = {};

  /// How many open return paths per partner. Carried along instead of counted:
  /// the map can have thousands of entries, and the cap is checked at
  /// EVERY remember.
  final Map<int, int> _proPartner = <int, int>{};

  int dropped = 0;
  int expired = 0;

  /// How often the PARTNER cap applied (not the global one).
  int droppedPerPartner = 0;

  PendingRequests({
    this.capacity = 1024,
    this.perPartner = 256,
    // ── THE PERIOD BELONGS TO THE RTT, NOT TO THE BACKLOG ─────────
    //
    // A first version of S357 set 32 minutes here, derived from
    // `kMaxControlBacklog x kSlotInterval` („backlog on both
    // sides"). **That was calculated on the wrong state**, and the
    // counter-reading overturned it: the backlog of up to 16 minutes
    // stands in the egress queue of the SENDER, and its book is
    // `V41Node._eigeneAblagen` — there the long period is right and
    // stands there too. An entry HERE only arises on
    // forwarding, i.e. after the frame has long left the sender's queue;
    // and forwarding happens with
    // `emitControl`, which sends IMMEDIATELY (answer traffic, appendix B-17,
    // not covered by the cover). Its lifetime is thus a
    // round-trip time, not a waiting time.
    //
    // Two minutes are generous for that — a multiple of every
    // measured hop-to-hop time — and at the same time short enough that
    // foreign state created disappears by itself. The 32 minutes
    // would have extended the attack surface from [perPartner] by a factor of 16
    // without saving a single honest return path.
    this.lifetime = const Duration(minutes: 2),
  });

  int get length => _open.length;

  static String _key(Uint8List id) => base64.encode(id);

  /// Remembers a forwarded request. `false` if there was no room.
  bool remember(Uint8List requestId, int fromPartner, DateTime now) {
    _sweep(now);
    final k = _key(requestId);
    final present = _open[k];
    if (present == null) {
      if (_open.length >= capacity) {
        dropped++;
        return false;
      }
      if ((_proPartner[fromPartner] ?? 0) >= perPartner) {
        droppedPerPartner++;
        return false;
      }
    } else if (present.partner != fromPartner) {
      // Same identifier over a different neighbour: the return path
      // changes, so who counts it changes as well.
      _proPartner[present.partner] =
          (_proPartner[present.partner] ?? 1) - 1;
      _proPartner[fromPartner] = (_proPartner[fromPartner] ?? 0) + 1;
      _open[k] = (partner: fromPartner, seen: now);
      return true;
    }
    if (present == null) {
      _proPartner[fromPartner] = (_proPartner[fromPartner] ?? 0) + 1;
    }
    _open[k] = (partner: fromPartner, seen: now);
    return true;
  }

  /// How many return paths this partner currently occupies. Only for display
  /// and tests.
  int openFor(int partner) => _proPartner[partner] ?? 0;

  /// The partner to whom an answer goes back — or `null`.
  ///
  /// The identifier is CONSUMED in the process: a request has one return path,
  /// not arbitrarily many. Otherwise a relay could push arbitrarily many
  /// answers into the same path with one identifier.
  int? takeRoute(Uint8List requestId, DateTime now) {
    _sweep(now);
    final e = _open.remove(_key(requestId));
    if (e != null) _relieve(e.partner);
    return e?.partner;
  }

  void _relieve(int partner) {
    final n = (_proPartner[partner] ?? 1) - 1;
    if (n <= 0) {
      _proPartner.remove(partner);
    } else {
      _proPartner[partner] = n;
    }
  }

  /// All return paths of a partner fall with its session.
  ///
  /// Without that a fallen neighbour keeps its share of the cap occupied until
  /// the period expires — and since the partner indices MOVE UP on
  /// removal (`V41Node._dropPartner` removes from a
  /// list), the entries would afterwards point to the wrong one anyway.
  void forgetPartner(int partner) {
    _open.removeWhere((_, v) => v.partner == partner);
    _proPartner.remove(partner);
    final higher = _proPartner.keys.where((k) => k > partner).toList()..sort();
    for (final k in higher) {
      _proPartner[k - 1] = _proPartner.remove(k)!;
    }
    final moved = <String, ({int partner, DateTime seen})>{};
    _open.forEach((k, v) {
      moved[k] =
          v.partner > partner ? (partner: v.partner - 1, seen: v.seen) : v;
    });
    _open
      ..clear()
      ..addAll(moved);
  }

  /// Only look, without consuming — for multi-part answers.
  int? peekRoute(Uint8List requestId, DateTime now) {
    _sweep(now);
    return _open[_key(requestId)]?.partner;
  }

  void _sweep(DateTime now) {
    if (_open.isEmpty) return;
    final route = <String>[];
    _open.forEach((k, v) {
      if (now.difference(v.seen) > lifetime) route.add(k);
    });
    for (final k in route) {
      final e = _open.remove(k);
      if (e != null) _relieve(e.partner);
      expired++;
    }
  }
}
