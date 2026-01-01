// Relay eligibility — who may be responsible at all (E-B).
//
// GATED, NOT WEIGHTED. Under weighted reputation a fresh
// Sybil identifier is only worth less, but still selectable — so it still helps the
// attacker. Under gated eligibility generating
// identifiers helps NOT AT ALL: whoever has not aged in does not get into the
// responsibility set. The attacker must set up his fleet T epochs BEFOREHAND
// and sustain it — that is ~10x runtime costs and
// leaves the signature of a standing fleet. Flash Sybil thus becomes
// impossible, not only expensive (M6, positive control C).
//
// WHO DECIDES THAT? Everyone for themselves. "Since when do I know this
// node" is a LOCAL observation — there is no authority that
// certifies entry data, and there is not supposed to be one (no fixed
// point, §1.2). Two nodes can judge the same peer differently;
// that is no error, but the design. An attacker gains nothing from it:
// he would have to be known long enough to EVERYONE who is to choose
// him.
//
// THE OTHER SIDE OF THE COIN, openly: a freshly joined HONEST
// node contributes nothing to responsibility for T epochs. The network
// grows in breadth more slowly than it could. The trade is deliberate.
//
// ══════════════════════════════════════════════════════════════════════
// WHAT IS COUNTED — AND WHY NOT "KNOWN SINCE WHEN" (S376, P4-2)
// ══════════════════════════════════════════════════════════════════════
//
// Until S376 the gate computed `ageIn = epoch - firstSeenEpoch`, and
// `firstSeenEpoch` arose on EVERY path that brought a position into the
// supply — also from pure BOARD KNOWLEDGE (`entries.onRemembered`
// -> `_learn`, fed among others by the entry cascade, i.e.
// by a public rendezvous board). `lastSeenEpoch` did not enter
// the decision at all.
//
// THE ATTACK that left open: two placements on a public
// board ten days apart. The attacker need NOT run for a single
// second in between. The observing node sees the record the first
// time (`firstSeenEpoch` = day 0) and the second time (day 10) — and
// computes `ageIn = 10 >= T`. "~10 days of standing, continuously
// paid-for fleet" (§10.3) had become two board placements. The
// runtime costs on which the whole M6 calculation rests were zero.
//
// SINCE THEN TWO DIFFERENT OPERATIONS, and the difference is the core:
//
//   [EligibilityRegistry.note]   — "I have heard of this
//     position". Board, cascade, peer announcement, passed-on record.
//     Keeps the peer in the register (expiry, bookkeeping) and does NOT count for
//     eligibility.
//
//   [EligibilityRegistry.credit] — "this position has PROVABLY worked
//     in this epoch". Only two sources: a session that came about
//     (`V41Node.adopt` — the handshake proves the static
//     key for exactly this `L_node`, and now) and an
//     authenticated placement receipt (`V41Node._placeAck`, behind
//     `verifyPlaceAck`). §22.7: "evidence, not acquaintance".
//
// WHAT IS COUNTED IS THE NUMBER OF DIFFERENT PROVEN EPOCHS, not the
// distance between the first and the last. Two proofs ten
// epochs apart are two, not ten. Ten epochs with one
// proof each are ten — that is the standing fleet that §10.3 demands.
//
// NOT GAPLESS, and that is a decision: what is demanded is
// [kAgingEpochs] DIFFERENT proven epochs within the window,
// not [kAgingEpochs] consecutive ones. An honest node that
// drops out for a day (restart, move, network change) should not start at
// zero. For the attacker that changes nothing in the calculation:
// he must actually have run in [kAgingEpochs] different epochs
// and performed work at THIS observer.
library;

import 'dart:typed_data';

/// How many epochs a node must age in (E-B: T ≈ 10).
///
/// With the 24 h epoch (E-J) that is ~10 days of standing, continuously
/// paid fleet before a single relay counts.
const int kAgingEpochs = 10;

/// How far back the proof bitmask reaches.
///
/// SIXTY AND NOT SIXTY-FOUR: the mask lies in a
/// signed 64-bit `int`, and a set bit 63 would make
/// it negative — the hex backup on disk would then have to carry a
/// special rule. Sixty epochs are two months at the 24 h epoch;
/// whoever has not proven ten epochs in two months is no
/// standing fleet.
///
/// The window is SLIDING: proofs that are older no longer count.
/// "Standing" means standing, not "stood once".
const int kPaidWindowEpochs = 60;

int _windowMask(int bits) =>
    bits <= 0 ? 0 : (bits >= 63 ? -1 >>> 1 : (1 << bits) - 1);

int _countBits(int x) {
  var n = 0;
  var v = x;
  while (v != 0) {
    v &= v - 1;
    n++;
  }
  return n;
}

/// What a node knows locally about a peer.
final class PeerAge {
  /// In which epoch this peer was seen for the FIRST time.
  ///
  /// PURE BOOKKEEPING, since S376 no longer a basis for decisions —
  /// "seen" means "someone named its record", and that can be
  /// produced for free. The number stays because it says something in the log and in the
  /// diagnosis.
  final int firstSeenEpoch;

  /// In which epoch last — controls solely the expiry
  /// ([EligibilityRegistry.expire]).
  final int lastSeenEpoch;

  /// The YOUNGEST epoch for which a proof exists. `-1` = none.
  final int anchorEpoch;

  /// Bitmask of the proven epochs. Bit `i` stands for
  /// `anchorEpoch - i`; bit 0 is thus [anchorEpoch] itself.
  final int paidBits;

  const PeerAge({
    required this.firstSeenEpoch,
    required this.lastSeenEpoch,
    this.anchorEpoch = -1,
    this.paidBits = 0,
  });

  /// How many DIFFERENT epochs in the window up to [epoch] are proven.
  ///
  /// What is counted is the half-open window
  /// `(epoch - kPaidWindowEpochs, epoch]`. Bit `i` stands for the epoch
  /// `anchorEpoch - i`, so:
  ///
  ///   * too OLD (`anchorEpoch - i <= epoch - window`) drops out —
  ///     "standing" means standing, not "stood once";
  ///   * in the FUTURE (`anchorEpoch - i > epoch`) likewise drops
  ///     out. That is no academic case: the question "had this
  ///     peer aged in ON THE REFERENCE DATE" is also asked backwards,
  ///     and a proof from tomorrow must not answer it.
  int paidIn(int epoch) {
    if (anchorEpoch < 0 || paidBits == 0) return 0;
    final offset = epoch - anchorEpoch;
    final top = kPaidWindowEpochs - offset; // bits < top are young enough
    final bottom = offset < 0 ? -offset : 0; // bits < lower bound are ahead
    if (top <= bottom) return 0;
    final mask = _windowMask(top) & ~_windowMask(bottom);
    return _countBits(paidBits & mask);
  }
}

/// The local view of the age of all known peers.
final class EligibilityRegistry {
  final int agingEpochs;
  final Map<String, PeerAge> _ages = <String, PeerAge>{};

  /// Is called when something has changed that should be saved.
  ///
  /// NEEDED SINCE S376: until then the saving hung on the dirty flag
  /// of the entry SUPPLY (`onEntriesChanged`), because the age changed
  /// exactly when the supply also changed. But a proof
  /// from a placement receipt does not touch the supply — without
  /// this flag it would be lost at the next restart, and the
  /// peer would age in anew.
  void Function()? onChanged;

  EligibilityRegistry({this.agingEpochs = kAgingEpochs});

  String _k(Uint8List position) =>
      position.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// "I have heard of this position."
  ///
  /// Board, cascade, peer announcement, passed-on record. That keeps
  /// the peer in the register and postpones its expiry — it does NOT
  /// make it eligible. Whoever suspects a proof here should read the header of this
  /// file: exactly this confusion was the finding.
  void note(Uint8List position, int epoch) {
    final k = _k(position);
    final prev = _ages[k];
    if (prev != null && prev.lastSeenEpoch == epoch) return;
    _ages[k] = PeerAge(
      firstSeenEpoch: prev?.firstSeenEpoch ?? epoch,
      lastSeenEpoch: prev == null
          ? epoch
          : (epoch > prev.lastSeenEpoch ? epoch : prev.lastSeenEpoch),
      anchorEpoch: prev?.anchorEpoch ?? -1,
      paidBits: prev?.paidBits ?? 0,
    );
    onChanged?.call();
  }

  /// "This position has provably worked in [epoch]."
  ///
  /// ONLY from a session that came about or an authenticated
  /// placement receipt. A second proof in the same epoch does not count
  /// twice — that is the point of the bitmask: the epoch is the
  /// counting unit, not the event. Otherwise a fleet would buy
  /// eligibility on a single day.
  void credit(Uint8List position, int epoch) {
    final k = _k(position);
    final prev = _ages[k];
    var anchor = prev?.anchorEpoch ?? -1;
    var bits = prev?.paidBits ?? 0;
    if (anchor < 0 || bits == 0) {
      anchor = epoch;
      bits = 1;
    } else if (epoch > anchor) {
      final push = epoch - anchor;
      bits = push >= kPaidWindowEpochs
          ? 1
          : ((bits << push) | 1) & _windowMask(kPaidWindowEpochs);
      anchor = epoch;
    } else {
      final i = anchor - epoch;
      if (i < kPaidWindowEpochs) bits |= 1 << i;
    }
    _ages[k] = PeerAge(
      firstSeenEpoch: prev?.firstSeenEpoch ?? epoch,
      lastSeenEpoch: prev == null || epoch > prev.lastSeenEpoch
          ? epoch
          : prev.lastSeenEpoch,
      anchorEpoch: anchor,
      paidBits: bits,
    );
    onChanged?.call();
  }

  PeerAge? ageOf(Uint8List position) => _ages[_k(position)];

  /// How many DIFFERENT epochs this peer has proven in the window.
  int paidEpochs(Uint8List position, int epoch) =>
      _ages[_k(position)]?.paidIn(epoch) ?? 0;

  /// May this peer be responsible in [epoch]?
  ///
  /// Unknown peers are NOT eligible — ignorance counts as
  /// "fresh", not as "all right". The other way round the gate could be
  /// bypassed by mere not-knowing.
  bool isEligible(Uint8List position, int epoch) =>
      paidEpochs(position, epoch) >= agingEpochs;

  /// Filters a candidate set down to the eligible ones.
  ///
  /// That is the seam to WP-0: `closestTo` computes the closeness, this gate
  /// decides who is a candidate at all. First filter, then sort —
  /// the other way round ineligible nodes would stand in the set and the
  /// responsibility would be smaller than R.
  Iterable<T> eligibleOnly<T>(
    Iterable<T> candidates,
    Uint8List Function(T) positionOf,
    int epoch,
  ) =>
      candidates.where((c) => isEligible(positionOf(c), epoch));

  int get known => _ages.length;
  int eligibleCount(int epoch) =>
      _ages.values.where((a) => a.paidIn(epoch) >= agingEpochs).length;

  // ── THE AGE MUST SURVIVE THE RESTART (§10.3, normative) ─────────────
  //
  // §10.3 names it as the first of two conditions "without which the
  // gate does harm rather than good": "`firstSeenEpoch` has to survive a
  // daemon restart. Held only in memory, every peer is 'fresh' after
  // every restart and the node finds no responsible relay for ten days —
  // an availability failure traded in for a Sybil fix."
  //
  // Until S354 this register lived exclusively in memory. The
  // failure would not even have been noticed: the gate only applies from
  // `eligibleCount >= R`, and after a restart this counter is 0 —
  // so the gate was open, and it looked like "running". Exactly the
  // class that has hit this migration several times: built,
  // ineffective, unremarkable.
  //
  // FORMAT v2 (S376): position (hex) -> [first, last, anchor,
  // proven-epochs-as-hex]. What MUST survive the restart are the
  // proofs — the two sighting dates are only bookkeeping now.
  //
  // v1 IS NOT READ, and that is no oversight. A v1 file
  // contains exactly the number that the finding rejected: a
  // first-capture date without a single proof behind it. Continuing
  // to compute with it would mean rescuing the attack across the format change.
  // V4.1 knows no data migration anyway (owner,
  // 08.09.2026) — the peers age in anew, and the gate lets them
  // through meanwhile (`eligibleCount >= R`, §10.3 condition 2).

  static const int formatVersion = 2;  // V3-TOUCH-OK: V4.1's own format version (tagline/), no V3 format — foreign versions are discarded, not migrated (owner 08.09.2026)

  Map<String, dynamic> toJson() => {
        'v': formatVersion,  // V3-TOUCH-OK: V4.1's own format version (tagline/), no V3 format — foreign versions are discarded, not migrated (owner 08.09.2026)
        'a': {
          for (final e in _ages.entries)
            e.key: [
              e.value.firstSeenEpoch,
              e.value.lastSeenEpoch,
              e.value.anchorEpoch,
              e.value.paidBits.toRadixString(16),
            ]
        },
      };

  /// Loads what [toJson] delivered. Returns whether anything was read.
  ///
  /// Unreadable content is silently skipped — a broken entry must not
  /// cost the whole supply, and a missing one only means "this
  /// peer ages in anew". A file with a foreign version is skipped
  /// ENTIRELY (see above).
  bool loadJson(Map<String, dynamic> j) {
    if (j['v'] != formatVersion) return false;  // V3-TOUCH-OK: V4.1's own format version (tagline/), no V3 format — foreign versions are discarded, not migrated (owner 08.09.2026)
    final a = j['a'];
    if (a is! Map) return false;
    for (final e in a.entries) {
      final k = e.key;
      final v = e.value;
      if (k is! String || v is! List || v.length < 4) continue;
      final first = v[0], last = v[1], anchor = v[2], bits = v[3];
      if (first is! int || last is! int || anchor is! int) continue;
      if (bits is! String) continue;
      final mask = int.tryParse(bits, radix: 16);
      if (mask == null || mask < 0) continue;
      _ages[k] = PeerAge(
        firstSeenEpoch: first,
        lastSeenEpoch: last,
        anchorEpoch: anchor,
        paidBits: mask & _windowMask(kPaidWindowEpochs),
      );
    }
    return true;
  }

  /// Throws away peers that have not been seen for [keepEpochs] epochs.
  ///
  /// OTHERWISE THE REGISTER GROWS WITHOUT LIMIT — it is the only structure
  /// of this layer that keeps every position ever seen. The deadline is
  /// generous (a multiple of the ageing time): whoever comes back should
  /// not have to age in anew, that is the explicit purpose of
  /// `lastSeenEpoch`.
  int expire(int epoch, {int keepEpochs = kAgingEpochs * 9}) {
    final route = <String>[];
    for (final e in _ages.entries) {
      if (epoch - e.value.lastSeenEpoch > keepEpochs) route.add(e.key);
    }
    for (final k in route) {
      _ages.remove(k);
    }
    if (route.isNotEmpty) onChanged?.call();
    return route.length;
  }
}
