import 'dart:convert';
import 'dart:typed_data';

import '../crypto/oqs_ffi.dart';
import '../crypto/sodium_ffi.dart';
import 'harvest_horizon.dart';
import 'message_seal.dart';

/// A one-time prekey — usable only ONCE, and **only X25519**.
///
/// NO ML-KEM IN IT, and that is not economy but arithmetic:
/// an ML-KEM-768 pubkey measures 1184 B, a cell carries 1043. A
/// hybrid prekey would **not fit individually** into a replenishment, a
/// batch of 16 even less (19.5 KB). §4.6 says so explicitly:
/// „One-time prekeys are plain X25519 keys: public 32 B, secret 32 B. The
/// ML-KEM component is a single daily prekey per identity, **not part of
/// the one-time pool**." A batch thus measures ~512 B and fits.
///
/// The PQ part comes from the DAILY CAPSULE (§4.3) and is not fetched anew per
/// message.
final class Prekey {
  /// The supply-wide house number of the receiver. It stands on the wire
  /// only in the REPLENISHMENT (`PrekeyBatchCodec`), so that the sender
  /// knows which pair it reports back; in the sealed cell
  /// it does NOT stand — there stands the hash selector (`PrekeySelector`).
  final int index;

  final Uint8List x25519Public;

  // HERE STOOD `epoch` — the day on which the prekey was minted
  // (dropped on 30.08.2026 with version B of §4.6).
  //
  // It existed for exactly two readers, and both disappeared with the
  // counter selector: it was one half of
  // `(epoch, n)`, and in the lookup it separated „long expired" from
  // „never existed". The hash selector carries no epoch and cannot
  // carry one — an expired prekey is deleted, so there is no
  // `pk_i` any more against which to hash. Re-measured after the rebuild:
  // ZERO readers apart from the encoding that wrote it itself and read it
  // again. A field that only keeps its own serialisation busy is
  // exactly the class „built, not entered" that has already cost this migration
  // money three times — so gone, together with its 4 B in the batch.
  //
  // What expiry measures instead: `V41Host.expiredPrekeysSwept`,
  // filled from [PrekeyPool.sweep].

  const Prekey(this.index, this.x25519Public);
}

/// A replenishment: 16 one-time X25519 prekeys **and the ML-KEM-768 pk
/// of this batch** (E1, S363).
///
/// ══════════════════════════════════════════════════════════════════════
/// WHY THE PQ PART NOW TRAVELS IN THE BATCH (E1)
/// ══════════════════════════════════════════════════════════════════════
///
/// Until S363 the PQ part came from the LONG-LIVED ML-KEM key of the
/// identity: the sender formed the daily capsule against it, and the
/// forward secrecy of this part depended solely on the clock by which
/// the identity rotated (§4.5.4, „every 7 days"). The batch itself
/// carried no PQ material.
///
/// That was the place where the 31 days broke. A clock rotation
/// forces an announcement, the announcement a period, and
/// whoever was away between two rotations sealed against a dead
/// key. E1 turns the quantity around: **the PQ key hangs on the
/// batch, not on a clock.** The selector names the prekey, the
/// prekey names its batch, the batch names exactly ONE
/// ML-KEM secret part — one decapsulation per capsule cell, as before.
///
/// **THE GRANULARITY IS FINER THAN BEFORE, NOT COARSER.** A batch
/// covers 8..16 messages or the period, whichever comes first; the
/// clock rotation covered 7 days, independent of traffic.
///
/// **THE PRICE, MEASURED.** A batch with the pk measures **1761 B** instead of
/// 577 B (`PrekeyBatchCodec`) — 1184 B per batch, i.e. 74 B per prekey
/// amortised. §4.6 rejected a hybrid prekey because it would have cost 1184 B
/// **per prekey** (19.5 KB per batch); this objection
/// does not hit the construction here. At the receiver there lie per living
/// batch 16 x 32 B + 2400 B = **2912 B**.
final class PrekeyBatch {
  /// Die oeffentlichen X25519-Anteile, in Ziehreihenfolge.
  final List<Prekey> keys;

  /// The ML-KEM-768 pubkey of THIS stack (1184 B).
  final Uint8List mlKemPublic;

  const PrekeyBatch(this.keys, this.mlKemPublic);
}

/// The counting space of the one-time prekeys of ONE IDENTITY.
///
/// ── WHY NOT PER CONTACT (S355) ────────────────────────────────────
///
/// The supplies are kept per contact (§4.6: „One pool … per
/// contact") — the counter must not be.
///
/// THE REASON CHANGED WITH VERSION B, the rule did not. Until
/// 30.08.2026 the index stood on the wire, and a counter starting at 0 per contact
/// would have confronted the opener with several identically named
/// secrets. The hash selector no longer names an index; the
/// index is purely the receiver's house number. It must still be
/// unique identity-wide, because it carries the DELETION:
/// `V41Host._oneTimeUsed` gets only the number from the hit and searches
/// it across all supplies (`v41_host.dart`). If there were a 3 in two
/// supplies, the receiver would delete the wrong prekey — and the
/// right one would stay: silently lost message AND cancelled
/// forward secrecy in one go.
///
/// §4.6 explicitly covers the identity-wide counting: „consumption
/// is counted **pool-wide**".
final class PrekeyIndexSpace {
  int _next = 0;

  int take() => _next++;

  /// How many indices have been assigned so far — for tests and diagnostics.
  int get issued => _next;

  /// Raises the counter so far that [index] counts as assigned.
  ///
  /// ── WHY THE COUNTER MUST NEVER RUN BACKWARDS ──────────────────
  ///
  /// The index carries the DELETION (see above): `V41Host._oneTimeUsed`
  /// gets only the number from the hit and searches it across all
  /// supplies. If the same number existed twice, the receiver would delete
  /// the wrong prekey — the right one would stay. That is silently
  /// lost message AND cancelled forward secrecy in one
  /// go, and both without any sign.
  ///
  /// After a restart exactly that is the danger: a counter starting
  /// again at 0 assigns numbers that still live on disk.
  /// That is why [loadJson] raises it to the saved state, and
  /// [PrekeyPool.loadJson] additionally raises it above every index it
  /// really loads — even if the saved counter is missing
  /// or unreadable. Two paths to the same protection, because one
  /// (`space`) can get lost and the other (the indices themselves)
  /// cannot: without them there would be nothing to protect.
  void ensurePast(int index) {
    if (index >= _next) _next = index + 1;
  }

  Map<String, Object?> toJson() => {'v': 1, 'next': _next};

  /// Loads what [toJson] supplied. Unreadable items are silently skipped
  /// — and the counter is only RAISED in the process, never lowered.
  void loadJson(Map<String, Object?> j) {
    if (j['v'] != 1) return;
    final n = j['next'];
    if (n is! int || n <= _next) return;
    _next = n;
  }
}

/// The supply at the RECEIVER (§4.6).
///
/// WHY RANDOM AND NOT DERIVED. The obvious thing would be to derive the pairs from
/// `K_AB` — then no transmission would be needed. But exactly that would
/// destroy what they are there for: whoever obtains `K_AB` could recompute EVERY
/// prekey and open everything retroactively. Forward secrecy
/// arises because a secret is DELETED and no one can
/// restore it. So rolled randomly, public part sent,
/// private part gone after use.
///
/// WHY THE RETENTION MUST BE LONGER THAN THE DELIVERY PERIOD. A
/// cell may rest for the full TTL. Whoever deletes the corresponding prekey before that
/// can no longer open it — and does not notice, because a
/// cell that cannot be opened looks like no cell. Hence 15 days:
/// delivery period plus margin.
final class PrekeyPool {
  /// How many pairs a replenishment covers.
  static const int batch = 16;

  /// From when on replenishment happens: less than half left.
  static const int refillBelow = batch ~/ 2;

  /// How long an unused prekey is retained — measured in
  /// SAMPLED epochs, not on the wall clock (see [horizon]).
  static const Duration retention = Duration(days: 15);

  /// The clock on which [retention] hangs (E5, S363).
  ///
  /// ── WHY NOT `now` (the finding) ─────────────────────────────────
  ///
  /// Until S363 [sweep] and [loadJson] had `now.difference(born)`.
  /// The second place is the serious one: [loadJson] runs AT START, before
  /// the first harvest. A device that was off for 31 days thereby threw away,
  /// at the moment of booting, every prekey older than [retention] —
  /// and only afterwards did the catch-up harvest start fetching the corresponding cells.
  /// The cells were still with the relay (the management class
  /// holds `kManagementKeepEpochs` = 31 epochs); only no one could
  /// open them any more. On the opener side the 31-day class was thus really a
  /// 15-day class.
  ///
  /// Instead of the wall clock, [HarvestHorizon] measures up to WHERE the harvest has
  /// sampled the epoch axis. In continuous operation both are the same;
  /// after an absence nothing falls before the gap is harvested.
  ///
  /// WITHOUT HAND-OVER THE FALLBACK. As with [space] this is right for tests
  /// and wrong for operation: there `V41Host` passes through its
  /// kept horizon, and `smoke_ernte_horizont.dart` measures
  /// that it really does.
  final HarvestHorizon horizon;

  /// THE PUBLIC PART IS KEPT ALONG, and that is new with version
  /// B: the selector is `SHA-256(pk_i ‖ eph_pk)`, so the receiver must
  /// recompute it over ITS own `pk_i`. In version A the
  /// index sufficed as key of the map; now the lookup is a
  /// probe over all entries ([matchSelector]), and that needs `pk_i`.
  /// Computing it from `sk_i` would cost 37.76 us per entry and per cell —
  /// so keep 32 B instead of generating them anew every time.
  final Map<
      int,
      ({
        Uint8List x25519Sk,
        Uint8List x25519Pk,
        DateTime born,
        int stack
      })> _secrets = {};

  /// The ML-KEM secret part PER BATCH (E1, S363) — 2400 B per entry.
  ///
  /// The key is the **house number of the first prekey** of this
  /// batch. It is unique identity-wide because all supplies
  /// share one [PrekeyIndexSpace]; a batch counter of its own would be
  /// a second quantity that says the same and can diverge.
  ///
  /// **IT FALLS WITH THE LAST `sk_i` OF ITS BATCH**, not on a clock of its
  /// own — §4.6 point 3 in the version of E1: „the receiver
  /// holds per batch 16 x 32 B `sk_i` AND the corresponding ML-KEM sk and
  /// throws both away together". Two periods for two halves
  /// of the same secret would be two opportunities to maintain the wrong one:
  /// if the ML-KEM sk falls earlier, the capsule-carrying cell is
  /// silently unopenable although its `sk_i` is still there.
  final Map<int, Uint8List> _stackKem = {};

  /// The house number under which a prekey WITHOUT batch is kept.
  ///
  /// It only arises when reading a stored item from the time before E1
  /// ([loadJson]): there was no batch KEM there, and the sender had
  /// encapsulated against the long-lived identity key. Such
  /// prekeys carry [withoutStack], and [matchSelector] returns for them
  /// `null` as batch secret — the opener then falls back to the
  /// identity generations, exactly as before E1.
  static const int withoutStack = -1;

  // HERE STOOD A SECOND MAP `_publics` (`Map<int, Prekey>`), dropped
  // on 30.08.2026. It was filled in `refill` and emptied in `consume`/`sweep`
  // and had in `lib/`, `bin/` and `test/` together ZERO readers
  // (measured). With version B `_secrets` holds the same public
  // part anyway — two stores for the same 32 B, one of which
  // no one reads, are an opportunity to maintain the wrong one.

  /// Where the indices come from. Without a passed space an own one — that
  /// is right for tests and wrong for operation: there all supplies of
  /// an identity MUST share one (see
  /// [PrekeyIndexSpace], `V41Host.poolFor`).
  final PrekeyIndexSpace space;

  PrekeyPool({PrekeyIndexSpace? space, HarvestHorizon? horizon})
      : space = space ?? PrekeyIndexSpace(),
        horizon = horizon ?? HarvestHorizon.wallClock();

  /// How many unused prekeys the supply still carries.
  int get unused => _secrets.length;

  /// Is a replenishment needed?
  bool get needsRefill => unused < refillBelow;

  /// Creates the next [batch] pairs, mints the **ML-KEM key
  /// of this batch** (E1) and returns both — that is the
  /// replenishment.
  ///
  /// ONE ML-KEM PAIR PER BATCH, not per prekey and not per clock. The
  /// reasoning including the calculated price is at [PrekeyBatch].
  ///
  /// THE HOUSE NUMBER OF THE FIRST PREKEY IS THE BATCH IDENTIFIER. It is
  /// assigned here and never changed again; [_stackKem] hangs on it.
  PrekeyBatch refill({required DateTime now}) {
    final out = <Prekey>[];
    final kem = OqsFFI().mlKemKeypair();
    var stack = withoutStack;
    for (var i = 0; i < batch; i++) {
      final idx = space.take();
      if (i == 0) stack = idx;
      final x = SodiumFFI().generateX25519KeyPair();
      _secrets[idx] = (
        x25519Sk: x.secretKey,
        x25519Pk: x.publicKey,
        born: now,
        stack: stack
      );
      out.add(Prekey(idx, x.publicKey));
    }
    _stackKem[stack] = kem.secretKey;
    return PrekeyBatch(out, kem.publicKey);
  }

  // HERE STOOD `int get stapelZahl => _stapelKem.length;` — an
  // information that ONLY guards would have read
  // (`smoke_delivery_layer_unwalked_guard` reported it immediately on 03.09.2026
  // as „known only to tests"). What it was supposed to measure is available via
  // [toJson]: the key `m` carries exactly the
  // batch secret parts this supply holds. A guard that reads the
  // STORED ITEM even measures more — namely also that the
  // secret part really travels along.

  /// Throws away the ML-KEM secret part as soon as its batch carries no
  /// unused `sk_i` any more — „both together" (§4.6 point 3
  /// in the version of E1).
  void _stackCleanUp(Iterable<int> touched) {
    for (final st in touched.toSet()) {
      if (st == withoutStack) continue;
      if (!_stackKem.containsKey(st)) continue;
      final stillThere = _secrets.values.any((e) => e.stack == st);
      if (!stillThere) _stackKem.remove(st);
    }
  }

  /// The prekey whose `SHA-256(pk_i ‖ eph_pk)` hits [selector] —
  /// WITHOUT consuming it.
  ///
  /// ── WHY A PROBE AND NOT A LOOKUP (version B) ───────────────
  ///
  /// The counter selector of version A WAS the index, so
  /// `_secrets[index]` sufficed, O(1). The hash selector hangs on `eph_pk`, which is fresh per
  /// cell — nothing can be precomputed and nothing
  /// indexed, the supply must be run through. As measured, a
  /// candidate costs 0.947 us (SHA-256 over 64 B), a supply thus 8..16 times
  /// that; compared with the 37.76 us of a scalar multiplication that
  /// trying through cost per candidate, the gain of §4.6
  /// remains. The full calculation including DoS cap is at
  /// `PrekeySelector`.
  ///
  /// WHY LOOKUP AND DELETION ARE SEPARATE. §4.6: „The receiver
  /// deletes `sk_i` immediately **after successful unsealing**." A
  /// relay on the path can intercept a real cell, corrupt its ciphertext
  /// and send it on: selector and `eph_pk` then still
  /// fit, this probe hits, the AEAD fails. Whoever deletes here
  /// lets his supply be emptied this way without a single
  /// message being lost — i.e. without any sign.
  ///
  /// The return value carries the index along so that the deletion site
  /// ([consume]) does not have to search the hit a second time.
  /// THE HIT CARRIES THE BATCH ML-KEM ALONG (E1, S363). The opener
  /// needs it at the same moment it gets the `sk_i`, and
  /// it must not have to search for it a second time: which batch
  /// was meant is fixed only here. `null` means „this prekey came
  /// from a stored item before E1" — then the identity generation applies.
  PrekeyMatch? matchSelector(Uint8List selector, Uint8List ephemeralPublic) {
    for (final e in _secrets.entries) {
      if (PrekeySelector.matches(
          selector, e.value.x25519Pk, ephemeralPublic)) {
        return PrekeyMatch(e.value.x25519Sk, e.key,
            mlKemSk: _stackKem[e.value.stack]);
      }
    }
    return null;
  }

  /// Does this supply know the index at all?
  bool holds(int index) => _secrets.containsKey(index);

  /// The private part for an index — and afterwards it is GONE.
  ///
  /// Exactly here the forward secrecy arises. Whoever postpones the deletion
  /// postpones it along.
  Uint8List? consume(int index) {
    final e = _secrets.remove(index);
    if (e != null) {
      _deletedInThisRun = true;
      // BOTH TOGETHER (E1). If that was the last `sk_i` of its batch,
      // the 2400-B ML-KEM secret part falls with it. Whoever left it
      // lying would hold a PQ key without any object — and
      // exactly that is the seizure window that E1 caps at
      // `Frist + 1 d`.
      _stackCleanUp([e.stack]);
    }
    return e?.x25519Sk;
  }

  /// Throws away what is too old. Returns how many.
  ///
  /// TOO OLD MEANS SINCE S363: the [horizon] is beyond `born + retention`,
  /// so the harvest has sampled the epochs in question once.
  /// Not: the wall clock is beyond it.
  int sweep(DateTime now) {
    final route = <int>[];
    final stack = <int>[];
    _secrets.forEach((i, e) {
      if (horizon.mayTraps(
          born: e.born, now: now, deadline: retention)) {
        route.add(i);
        stack.add(e.stack);
      }
    });
    for (final i in route) {
      _secrets.remove(i);
    }
    if (route.isNotEmpty) _deletedInThisRun = true;
    // BOTH TOGETHER (E1) — see [consume].
    _stackCleanUp(stack);
    return route.length;
  }

  /// The house numbers this supply currently carries — for tests and
  /// for the host, which determines the highest assigned index from them.
  Iterable<int> get indices => _secrets.keys;

  // ── THE STORED ITEM (S356) ──────────────────────────────────────────────
  //
  // WHY IT MUST EXIST. Until S356 this supply had no
  // persistence whatsoever — re-measured: no `toJson`, no `loadJson`, in `lib/`,
  // `bin/` and `test/` not a single place. The one-time prekeys of a
  // receiver disappeared at EVERY process start. §21.4 demands the
  // opposite and names them explicitly: the object lies
  // "mandatorily under the DB key, together with `inbox_key` and the
  // prekey pool (§4.6)". §4.6 point 3 also says what the loss costs:
  // retention must outlast the full delivery period, "or cells
  // from days 9-14 become unopenable (silent message loss)".
  //
  // It became urgent with S355: since `BootstrapPrekeys.oneTimePrekeysWired`
  // is in place and `sendFrame` calls `refillIfNeeded`, replenishments really
  // flow. The sender then seals against a one-time prekey; a
  // restart of the receiver in between makes the cell fail already at the
  // candidate probe — in the log only as "kein Prekey-Kandidat
  // passte" (`MessageOpener.unresolvedSelectors`). That is a
  // PREDICTION from the code, not yet observed in the field.
  //
  // WHAT THIS INTERFACE DOES NOT DO: it does not write and it does not
  // encrypt. It supplies and takes a structure, nothing
  // more — the storing is hooked in by `v41_attach.dart` against `FileEncryption`,
  // just as it already hooks in the entry supply and the peer age.
  //
  // NO `toJsonString`, AND THAT IS INTENTIONAL. `EntryStore` has one —
  // there these are public address records. Here they are SECRET
  // keys. A convenient string form is the one line someone puts
  // into a `File(...).writeAsString(...)`, and then 16
  // `sk_i` per contact lie in plaintext on disk. Whoever stores them should
  // have to go through `FileEncryption`.

  /// Whether in THIS run a secret from this supply has already disappeared
  /// — through [consume] or [sweep].
  bool _deletedInThisRun = false;

  /// Whether this supply still accepts a stored item.
  ///
  /// See [loadJson]: it does so only as long as nothing was deleted
  /// in this run.
  bool get acceptsSnapshot => !_deletedInThisRun;

  /// THE BATCH ML-KEM TRAVELS ALONG (E1, S363). Without it, after a
  /// restart every capsule-carrying cell would be unopenable — the same class
  /// because of which `sk_i` has been stored at all since S356, only one
  /// half further.
  ///
  /// CONTAINS TWO KINDS OF SECRET KEYS. Store only encrypted.
  Map<String, Object?> toJson() => {
        'v': 1,
        'k': [
          for (final e in _secrets.entries)
            {
              'i': e.key,
              's': base64.encode(e.value.x25519Sk),
              'p': base64.encode(e.value.x25519Pk),
              'b': e.value.born.millisecondsSinceEpoch,
              'st': e.value.stack,
            }
        ],
        'm': {
          for (final e in _stackKem.entries)
            e.key.toString(): base64.encode(e.value),
        },
      };

  /// Loads what [toJson] supplied. Returns how many entries
  /// were really taken over.
  ///
  /// ── THE CONSUMED PREKEY MUST STAY CONSUMED ─────────────────
  ///
  /// A stored item is a picture of the past. If it is played back into a
  /// supply from which an `sk_i` has since been deleted,
  /// the secret is there again — and forward secrecy is
  /// silently and permanently cancelled, without anything failing
  /// anywhere. That is why a supply that has already
  /// deleted in this run ([acceptsSnapshot] `false`) accepts nothing at all and
  /// returns 0.
  ///
  /// That is stricter than necessary and intentionally so: the intended path is
  /// „once at start, into a fresh supply". A second load
  /// in the middle of operation is not a use case this layer knows —
  /// and a protection that only holds with correct use is none.
  ///
  /// WHAT THE PERIOD THROWS AWAY DOES NOT COME BACK. Entries older
  /// than [retention] already fall here (§4.6 point 3) — otherwise
  /// a restart would have reset the period and the supply would grow
  /// beyond every limit.
  ///
  /// **AND EXACTLY HERE LAY THE FINDING (E5, S363).** „Older than
  /// [retention]" meant wall-clock time, and this line runs BEFORE the
  /// first harvest. A device absent for 31 days thereby deleted, at the
  /// moment of loading, the keys to cells that were still lying at the relay
  /// and that it would have fetched seconds later. Since S363
  /// this line asks the [horizon] — the period counts in sampled
  /// epochs. The cap against unlimited growth is not
  /// gone, it sits in [HarvestHorizon.capViaDeadline].
  ///
  /// UNREADABLE ITEMS ARE SILENTLY SKIPPED. A broken entry must not
  /// cost the whole supply; what is missing the sender runs over the
  /// static fallback — visible in `fallbackCount`, not
  /// silent.
  int loadJson(Map<String, Object?> j, {required DateTime now}) {
    if (j['v'] != 1) return 0;
    if (!acceptsSnapshot) return 0;
    final k = j['k'];
    if (k is! List) return 0;
    var taken = 0;
    for (final item in k) {
      if (item is! Map) continue;
      final i = item['i'];
      final s = item['s'];
      final p = item['p'];
      final b = item['b'];
      if (i is! int || i < 0 || s is! String || p is! String || b is! int) {
        continue;
      }
      final born = DateTime.fromMillisecondsSinceEpoch(b);
      if (horizon.mayTraps(
          born: born, now: now, deadline: retention)) {
        continue;
      }
      final Uint8List sk;
      final Uint8List pk;
      try {
        sk = Uint8List.fromList(base64.decode(s));
        pk = Uint8List.fromList(base64.decode(p));
      } catch (_) {
        continue;
      }
      // 32 B per half — §4.6: „public 32 B, secret 32 B". A
      // deviating entry would only show up deep in libsodium.
      if (sk.length != cryptoScalarMultScalarBytes ||
          pk.length != cryptoScalarMultBytes) {
        continue;
      }
      // WITHOUT `st` „NO BATCH" APPLIES (E1). A stored item from the time before
      // E1 carries none; its prekeys were encapsulated against the long-lived
      // identity KEM, and exactly there the opener falls
      // back when [matchSelector] returns `null` as batch secret.
      // Pinning it here onto an arbitrary batch would be worse
      // than no batch: the opener would then compute with the wrong
      // ML-KEM secret part and leave the right branch unchecked.
      final st = item['st'];
      _secrets[i] = (
        x25519Sk: sk,
        x25519Pk: pk,
        born: born,
        stack: st is int ? st : withoutStack
      );
      // THE COUNTER MUST KNOW THIS INDEX, even if the saved
      // counter state was missing or unreadable. Otherwise the next
      // replenishment assigns a number that has just come back to life here.
      space.ensurePast(i);
      taken++;
    }
    // ── THE BATCH SECRET PARTS, AND AFTER THE PREKEYS ────────────
    //
    // After them, because here only what still has a
    // living `sk_i` is taken over. An ML-KEM secret part without a batch would be
    // held PQ material without any object — it can no longer open any cell
    // (the selector finds no prekey), but it extends
    // the seizure window. The period is the same as that of the
    // prekeys, so it falls here together.
    final m = j['m'];
    if (m is Map) {
      final living = <int>{for (final e in _secrets.values) e.stack};
      for (final e in m.entries) {
        final st = int.tryParse('${e.key}');
        final value = e.value;
        if (st == null || st == withoutStack || value is! String) continue;
        if (!living.contains(st)) continue;
        final Uint8List sk;
        try {
          sk = Uint8List.fromList(base64.decode(value));
        } catch (_) {
          continue;
        }
        if (sk.length != OqsFFI.mlKemSecretKeyLength) continue;
        _stackKem[st] = sk;
      }
    }
    return taken;
  }
}

/// A draw: the one-time prekey and the ML-KEM pk of ITS batch
/// (E1, S363).
///
/// ── WHY THE TWO COME OUT TOGETHER ────────────────────────────
///
/// Because they must be used together. The sender forms the
/// selector and the Diffie-Hellman from [key] and the capsule from
/// [stackMlKem]; if the two came from two separate pieces of information,
/// they could diverge — the receiver would find via the
/// selector the right prekey, decapsulate with the ML-KEM secret part
/// of ITS batch and get a different `ss_pq`. The AEAD fails, the
/// message is silently gone.
///
/// The same reasoning struck `selectorFor` on 30.08.: two
/// pieces of information about the same draw are an opportunity to answer them
/// differently.
final class PrekeyMove {
  final Prekey key;

  /// `null` means „from a stored item before E1" — then the long-lived
  /// identity KEM applies, as before E1.
  final Uint8List? stackMlKem;

  const PrekeyMove(this.key, this.stackMlKem);
}

/// What the SENDER knows of a counterpart's prekeys.
///
/// ══════════════════════════════════════════════════════════════════════
/// SINCE S363 THE BATCH CARRIES ITS AGE (E6)
/// ══════════════════════════════════════════════════════════════════════
///
/// THE FINDING. [Prekey] carries `index` and `x25519Public` and nothing
/// else — in particular no timestamp (re-measured 03.09.2026,
/// `prekey_pool.dart:19-45`). The sender thus did not know how old its
/// supply is. The RECEIVER by contrast throws away unused `sk_i` after
/// [PrekeyPool.retention] = 15 days. A sender that was away for 16 days
/// thus kept sealing against keys the receiver had
/// deleted: the hash selector hits nothing, the cell counts
/// at the receiver as `MessageOpener.unresolvedSelectors` and cannot be told apart from
/// a foreign cover cell. Silent loss,
/// independent of any key rotation.
///
/// ══════════════════════════════════════════════════════════════════════
/// THIS ROUND BUILDS THE KNOWLEDGE, NOT THE BLOCK — and that is intentional
/// ══════════════════════════════════════════════════════════════════════
///
/// The obvious version would be: [take] no longer returns anything
/// older than the period. **Today that would be a dead end.** E6
/// belongs together with E4 („if the batch is too old, the sender ASKS for
/// fresh material", S363 proposal section 7). E4 is not yet
/// built. Whoever blocks now takes the material away from the sender and gives him
/// no way to get any: he then sends NOT AT ALL, where
/// today he at least still sends — in vain, but without a dead end.
///
/// So: the batch carries its age, a batch that is too old is
/// **reported** ([report]) and **counted** ([staleDraws]), and
/// [take] keeps handing it out. The block comes with E4, at this place,
/// and then with a way back next to it.
///
/// The order is stated here so that the next reader does not take the missing
/// block for an omission.
final class PeerPrekeys {
  /// Per counterpart the known prekeys — **in draw order** and each
  /// with the time at which this batch arrived.
  ///
  /// THE RECEIVE TIME AND NOT THE MINTING, and the difference
  /// deserves to be named: the receiver stamps `born` at minting
  /// ([PrekeyPool.refill]), the replenishment then travels normatively over
  /// Secure to the sender (§4.6). `received >= born`, so the sender estimates
  /// its material TOO YOUNG by the transit time. That is the unsafe
  /// direction, and it is bounded by the transit time of a
  /// Secure delivery — minutes to hours against a period of 15
  /// days. Sending the real `born` along would cost 8 B per prekey on the
  /// wire and in EVERY replenishment; the S363 proposal explicitly decides
  /// for the receive time.
  ///
  /// SINCE E1 THE ML-KEM PUBKEY OF ITS BATCH HANGS ON EACH ENTRY.
  /// It is ONE object per batch, shared by all 16 entries — in
  /// memory 1184 B per batch, not per prekey. It must hang on the entry
  /// and not on the counterpart: a sender can simultaneously carry two
  /// batches of the same contact (the old one not yet
  /// used up, the new one already arrived), and every draw must
  /// name EXACTLY the pk its prekey belongs to. A pk „per
  /// counterpart" would, after the first replenishment, be the wrong one for the
  /// rest of the old batch — and the capsule would run against a
  /// secret part the receiver does not carry for this `sk_i`.
  final Map<
      String,
      List<
          ({
            Prekey key,
            DateTime receive,
            Uint8List? stackMlKem
          })>> _byPeer = {};

  /// Where a stale batch is reported. `null` = no one listens
  /// (tests); the counter [staleDraws] runs anyway.
  ///
  /// NO `CLogger` HERE. This file is pure data keeping without
  /// side effect; a `CLogger` hangs a timer on the process (S360:
  /// „CLogger held EVERY process"). `v41_attach.dart` hooks in its
  /// existing log sink.
  void Function(String message)? report;

  /// How often [take] drew a prekey from a batch that was too old.
  ///
  /// That is the measure of E6: it counts exactly the cells that
  /// will end at the receiver as `unresolvedSelectors`. Before S363 there was
  /// no number at all for this loss.
  int staleDraws = 0;

  /// From when on a batch counts as stale.
  ///
  /// **The same number as the retention at the receiver, and
  /// derived, not copied.** A prekey is dead exactly when the
  /// receiver has thrown away its `sk_i`, and it does that after
  /// [PrekeyPool.retention].
  static const Duration stackStaleFrom = PrekeyPool.retention;

  /// When the next prekey to be drawn of this counterpart arrived.
  ///
  /// The FRONTMOST, not the youngest: [take] takes from the front, so the
  /// age of the frontmost is the age of what goes onto the
  /// wire next.
  DateTime? receiveAt(String peer) {
    final l = _byPeer[peer];
    return (l == null || l.isEmpty) ? null : l.first.receive;
  }

  /// How old the batch of this counterpart is. `null` = no batch.
  Duration? stackAge(String peer, DateTime now) {
    final e = receiveAt(peer);
    return e == null ? null : now.difference(e);
  }

  /// Whether the batch of this counterpart is so old that the receiver
  /// is likely to have thrown away its secrets for it.
  ///
  /// No batch is NOT stale — that is a different situation (step 3
  /// of the ladder, visible in `fallbackCount`), and it has its own
  /// treatment.
  bool stackStale(String peer, DateTime now) {
    final e = receiveAt(peer);
    return e != null && _deadAt(e, now);
  }

  /// Whether ONE entry is dead. The one calculation on which
  /// [stackStale] and [dropDeadBeforeFresh] rely — two
  /// calculations side by side would be exactly the drift [take]
  /// warns about further below.
  bool _deadAt(DateTime received, DateTime now) =>
      now.difference(received) > stackStaleFrom;

  /// Throws away the dead HEAD of the batch — but only if there is
  /// fresh material behind it. Returns how many entries fell.
  ///
  /// ── WHY THIS METHOD EXISTS SINCE S367 ─────────────────────────
  ///
  /// [receive] APPENDS, it does not replace (`addAll`, see there). After
  /// a replenishment the list is thus `[old …, fresh …]`, and
  /// [receiveAt] names the OLD one — it goes out next. That is
  /// right as long as [take] really hands out the old one too.
  ///
  /// Since S367 it no longer does: `V41Host.sendFrame` seals with a
  /// stale batch under the pair anchor and DOES NOT DRAW. Without this
  /// method the dead head would thus stay at the front forever — the
  /// batch would count as stale forever, and the fresh material
  /// behind it would never get its turn. „The anchor only when the
  /// batch is stale" (variant E) would in practice have become „the anchor
  /// always" (variant B), and the per-message forward secrecy
  /// would be permanently gone for this pair.
  ///
  /// ── WHY ONLY BEFORE FRESH ────────────────────────────────────────
  ///
  /// If the WHOLE batch is dead, it stays. Two reasons, and both
  /// count:
  ///
  ///   * The sender estimates its material TOO YOUNG, not too old (the
  ///     receive time lies after the minting, see [_byPeer]) —
  ///     but since E5 the receiver's period hangs on the
  ///     harvest horizon, not on the wall clock. A receiver that was away
  ///     for a long time can therefore still hold its `sk_i`. Throwing away what
  ///     may still live would be a loss without benefit.
  ///   * There is nothing to gain: if nothing fresh lies behind it,
  ///     throwing away changes nothing at the switch — the anchor
  ///     is taken anyway.
  ///
  /// So only what lies IN THE WAY of a living entry is thrown
  /// away.
  int dropDeadBeforeFresh(String peer, DateTime now) {
    final l = _byPeer[peer];
    if (l == null || l.isEmpty) return 0;
    var dead = 0;
    while (dead < l.length && _deadAt(l[dead].receive, now)) {
      dead++;
    }
    // `tot == l.length`: everything dead — leave it lying (reasoning above).
    if (dead == 0 || dead == l.length) return 0;
    l.removeRange(0, dead);
    // TO BE TREATED LIKE A DRAW, and for the same reason: the list
    // is changed. If it accepted a stored item afterwards, the
    // dead entries would come back to life and lie in the way of the fresh material
    // again. See [acceptsSnapshot].
    _takenInThisRun = true;
    return dead;
  }

  void receive(String peer, PrekeyBatch batch, {DateTime? received}) {
    if (batch.keys.isEmpty) return;
    final t = received ?? DateTime.now().toUtc();
    // ONE object for all 16 — see [_byPeer].
    final kem = batch.mlKemPublic.isEmpty ? null : batch.mlKemPublic;
    _byPeer.putIfAbsent(peer, () => []).addAll([
      for (final k in batch.keys)
        (key: k, receive: t, stackMlKem: kem),
    ]);
  }

  int remaining(String peer) => _byPeer[peer]?.length ?? 0;

  /// Takes the next unused one — and puts it back into nothing.
  ///
  /// A prekey is used ONCE. Whoever takes it twice cancels the
  /// one-time property, and thus the whole purpose.
  ///
  /// A BATCH THAT IS TOO OLD IS REPORTED AND HANDED OUT NEVERTHELESS — the
  /// reasoning is above at the class header (E6 without E4 would be a
  /// dead end). Whoever inserts a `return null` here before E4 is in place
  /// takes the last path away from the sender.
  PrekeyMove? take(String peer, {DateTime? now}) {
    final l = _byPeer[peer];
    if (l == null || l.isEmpty) return null;
    final t = now ?? DateTime.now().toUtc();
    // ASKED BEFORE DRAWING, because afterwards the frontmost is a different one.
    // AND VIA [stapelVeraltet]/[stapelAlter], not with a second
    // calculation next to it: an information that the application answers
    // differently from the draw is exactly the drift in which
    // later no one can see which of the two is right.
    final stale = stackStale(peer, t);
    final age = stackAge(peer, t)!;
    final e = l.removeAt(0);
    _takenInThisRun = true;
    if (stale) {
      staleDraws++;
      report?.call('Prekey stack for $peer is ${age.inDays} days old '
          '(limit ${stackStaleFrom.inDays} d) — the recipient has probably '
          'thrown away his sk_i; it is sealed anyway '
          '(E4 missing, S363). So far ${staleDraws}x.');
    }
    return PrekeyMove(e.key, e.stackMlKem);
  }

  /// Only look — for the question whether a replenishment is needed.
  Prekey? peek(String peer) {
    final l = _byPeer[peer];
    return (l == null || l.isEmpty) ? null : l.first.key;
  }

  // ── THE STORED ITEM (S356) ──────────────────────────────────────────────
  //
  // WHY THIS SIDE IS SAVED TOO, although no secrets lie
  // here. The loss is a different one than for the own supply, but it
  // is not smaller:
  //
  //   * If `PrekeyPool` gets lost, the receiver cannot open incoming
  //     cells — silent message losses.
  //   * If THIS list gets lost, the sender falls back to the static
  //     key (step 3 of the ladder, §4.6) — visible in
  //     `fallbackCount`, so no loss. Only it does not end by
  //     itself: replenishment happens when the counterpart's OWN supply
  //     falls below B/2 (`V41Host.refillIfNeeded`), and it does not fall,
  //     because no one draws on it any more. Until the 15-day period empties the
  //     other side's supply in one go, the pair runs without
  //     forward secrecy — anew after EVERY restart.
  //
  // A restart that switches off forward secrecy for up to 15 days
  // is not an edge case. That is why this side travels in the same
  // stored item.
  //
  // THE PRICE, AND IT MUST BE NAMED. Between [take] and the
  // next save there is a window. If the process crashes within it,
  // an already consumed prekey comes back to life, the sender
  // seals against it a second time — and the receiver has long deleted its
  // `sk_i`: ONE message is silently lost. The
  // window is as large as the interval between draw and save;
  // `V41Host.prekeyStateDirty` marks exactly this moment so that
  // the construction site can write immediately afterwards.
  //
  // A second load in the middle of operation is rejected, for the same
  // reason as with [PrekeyPool.loadJson]: it would bring drawn prekeys
  // back to life, and not in a crash window, but
  // with certainty.

  bool _takenInThisRun = false;

  /// Whether this list still accepts a stored item — only as long as nothing
  /// was drawn in this run.
  bool get acceptsSnapshot => !_takenInThisRun;

  /// THE RECEIVE TIME TRAVELS ALONG (E6, S363). Without it every
  /// restart would reset the batch age to zero — and exactly the case at
  /// issue (a sender that was away for a long time) is a restart.
  ///
  /// THE BATCH PK IS STORED ONCE, NOT SIXTEEN TIMES (E1). It measures 1184 B;
  /// written per entry that would be 19.5 KB per batch and counterpart,
  /// with 20 contacts almost 400 KB for a file that is rewritten at every draw.
  /// The entries therefore only name the number
  /// of an entry in [`m`], and equal pks share a number.
  Map<String, Object?> toJson() {
    final kems = <String>[];
    final number = <String, int>{};
    int forField(Uint8List? pk) {
      if (pk == null || pk.isEmpty) return -1;
      final b = base64.encode(pk);
      return number.putIfAbsent(b, () {
        kems.add(b);
        return kems.length - 1;
      });
    }

    final p = <String, Object?>{};
    for (final e in _byPeer.entries) {
      p[e.key] = [
        for (final k in e.value)
          {
            'i': k.key.index,
            'p': base64.encode(k.key.x25519Public),
            'e': k.receive.millisecondsSinceEpoch,
            'm': forField(k.stackMlKem),
          }
      ];
    }
    return {'v': 1, 'p': p, 'm': kems};
  }

  /// Loads what [toJson] supplied. Returns how many prekeys
  /// were taken over. Unreadable items are silently skipped.
  ///
  /// THE ORDER IS PRESERVED, and that is not cosmetics: [take]
  /// takes from the front, the receiver clears up by `born`. Whoever
  /// re-sorts the list first reaches for the prekeys that expire first.
  int loadJson(Map<String, Object?> j, {DateTime? loaded}) {
    final loadedAt = loaded ?? DateTime.now().toUtc();
    if (j['v'] != 1) return 0;
    if (!acceptsSnapshot) return 0;
    final p = j['p'];
    if (p is! Map) return 0;
    // ── THE BATCH PKS, ONCE FOR ALL ENTRIES (E1) ──────────────
    //
    // Unreadable items stay `null`: the sender then falls back for this prekey
    // to the long-lived identity KEM ([PoolPrekeys]) — that
    // is the state before E1 and no loss, whereas a guessed pk
    // would produce a capsule no one can open.
    final kems = <Uint8List?>[];
    final mList = j['m'];
    if (mList is List) {
      for (final e in mList) {
        if (e is! String) {
          kems.add(null);
          continue;
        }
        try {
          final pk = Uint8List.fromList(base64.decode(e));
          kems.add(pk.length == OqsFFI.mlKemPublicKeyLength ? pk : null);
        } catch (_) {
          kems.add(null);
        }
      }
    }
    var taken = 0;
    for (final e in p.entries) {
      final peer = e.key;
      final list = e.value;
      if (peer is! String || peer.isEmpty || list is! List) continue;
      final batch = <({
        Prekey key,
        DateTime receive,
        Uint8List? stackMlKem
      })>[];
      for (final item in list) {
        if (item is! Map) continue;
        final i = item['i'];
        final b = item['p'];
        if (i is! int || i < 0 || b is! String) continue;
        final Uint8List pk;
        try {
          pk = Uint8List.fromList(base64.decode(b));
        } catch (_) {
          continue;
        }
        if (pk.length != cryptoScalarMultBytes) continue;
        // WITHOUT TIMESTAMP THE BATCH COUNTS AS OF UNKNOWN AGE, i.e. as
        // JUST ARRIVED — that is the version before E6 and the
        // state in which an old stored item exists. Setting it to `epoch 0`
        // would colour every old stock stale immediately and fill the
        // counter with cases no one measured.
        final e = item['e'];
        final m = item['m'];
        batch.add((
          key: Prekey(i, pk),
          receive: e is int
              ? DateTime.fromMillisecondsSinceEpoch(e, isUtc: true)
              : loadedAt,
          stackMlKem: (m is int && m >= 0 && m < kems.length) ? kems[m] : null,
        ));
      }
      if (batch.isEmpty) continue;
      _byPeer.putIfAbsent(peer, () => []).addAll(batch);
      taken += batch.length;
    }
    return taken;
  }
}

/// Prekey source with real forward secrecy (§4.6).
///
/// The contrast to `StaticKeyPrekeys`: there these are the static
/// keys and a key obtained later opens everything. Here
/// every prekey is one-time and deleted at the receiver after use.
final class PoolPrekeys implements PrekeySource {
  final PeerPrekeys pool;

  /// The FALLBACK for the PQ part: the long-lived ML-KEM key
  /// of the counterpart.
  ///
  /// ── SINCE E1 THIS IS THE FALLBACK AND NO LONGER THE REGULAR CASE ─────
  ///
  /// Until S363 the PQ part ALWAYS came from here: the daily capsule was
  /// formed against the long-lived key of the identity, and a
  /// batch carried no PQ material. With E1 every batch carries its
  /// own ML-KEM-768 pk, and [mlKemPublicFor] takes that of the batch
  /// that was just drawn from.
  ///
  /// This fallback still applies in exactly two situations, and both are
  /// intended: (1) a stored item from the time before E1 carries no
  /// batch pk; (2) the counterpart has not yet sent a batch —
  /// then [advance] does not draw at all, and `BootstrapPrekeys` is on
  /// the static fallback anyway (step 3 of the ladder, §4.6).
  final Uint8List Function(String peer) mlKemOf;

  /// The last taken prekey per counterpart — both halves of a
  /// sealing must take THE SAME one, and since E1 that applies to
  /// THREE halves: `pk_i` carries the selector AND the Diffie-Hellman,
  /// the batch pk the capsule. They therefore lie in ONE record.
  final Map<String, PrekeyMove> _current = {};

  PoolPrekeys(this.pool, {required this.mlKemOf});

  /// Draws the next prekey. Returns `false` if none is left —
  /// then a replenishment is missing, and there is NO evasion to static
  /// keys. Silently switching off forward secrecy
  /// would be worse than not sending.
  bool advance(String peer, {DateTime? now}) {
    final p = pool.take(peer, now: now);
    if (p == null) return false;
    _current[peer] = p;
    return true;
  }

  /// The index against which sealing last happened.
  int? indexFor(String peer) => _current[peer]?.key.index;


  // HERE STOOD `selectorFor(peer)` — the second information of the source from
  // which the sender built the selector `(epoch, n)` (dropped on
  // 30.08.2026 with version B).
  //
  // It is not replaced but has become superfluous: the selector
  // is now computed from the public part that
  // [x25519PublicFor] supplies anyway (`message_seal.dart`, `seal`). The
  // drift its comment warned about — two sources, two draws,
  // one silently unopenable message — is thus no longer possible,
  // instead of only being carefully avoided.

  /// THE BATCH NAMES THE CAPSULE KEY (E1, S363). Not the clock
  /// of the identity: the receiver finds via the selector the prekey,
  /// via the prekey the batch and via the batch EXACTLY ONE
  /// ML-KEM secret part — one decapsulation per capsule cell.
  @override
  Uint8List mlKemPublicFor(String peer) =>
      _current[peer]?.stackMlKem ?? mlKemOf(peer);

  @override
  Uint8List x25519PublicFor(String peer) {
    final p = _current[peer];
    if (p == null) throw StateError('no prekey drawn for $peer');
    return p.key.x25519Public;
  }

  @override
  bool get providesForwardSecrecy => true;
}
