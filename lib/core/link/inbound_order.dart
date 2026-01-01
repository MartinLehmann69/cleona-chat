/// The order in which an arriving wire unit is classified (normative,
/// E-95, E-79, E-104, E-122).
///
/// **Why this is a module and not a comment.** Until E-122 the order lived
/// in one place — the UDP demux — as straight-line code with a long
/// explanatory header. That was enough while there was one transport. With
/// `tcpOwnPort` there are two receiving paths, and an order that has to
/// hold in two places is an order that eventually holds in one. The
/// difference is not visible in a green test: both paths classify the same
/// units into the same branches either way. It is visible from **outside**,
/// as a timing difference, which is the one place this project cannot
/// afford to be wrong.
///
/// **What the order is.**
///
/// 1. Both MAC families are computed **unconditionally**, for every unit,
///    before anything else is looked at (E-95). The disjunction stands only
///    after every call has returned.
/// 2. Only then may variable work run — expiry, bookkeeping, anything whose
///    cost depends on how much state this node holds. It ran *before* the
///    MAC check once and was measured at 6.2 µs against 145 µs at 4,096
///    entries; that is constant-time work behind variable work, which is the
///    wrong way round.
/// 3. A MAC match ends the unit. It goes to the responder path and **never**
///    falls through to a table lookup — not even when the responder path
///    rejects it. A replayed `init` that fell through would cost *more* work
///    than a forgery, and that difference is measurable (E-79, E-104
///    obligation ii).
/// 4. Only a unit whose MAC did not match reaches the tables, and there the
///    outbound handshake is asked before the established session.
///
/// The reverse of step 1 — tables first, MACs on a miss — is cheaper in the
/// normal case and was rejected for it: the branch is readable from outside
/// as "do you know me?", the same class of leak E-87 and E-95 each pay real
/// cost to avoid.
///
/// **How this file enforces the order rather than describing it.** Two
/// devices, and it took a hostile review to find that one of them was
/// missing. First: the caller does not hand in booleans — it hands in
/// *thunks*. [classify] calls [LinkHandshake.acceptsInitMac] itself, first
/// and exactly once, and the thunks are unreachable before it has returned.
/// Second: variable work is handed in as a callback that demands a
/// [MacChecked] — a token only this file can mint. Without the second
/// device the first covers only the *lookups*; any other state-dependent
/// work could still be hoisted in front of the MAC, and measurably was:
/// with `_expire()` moved ahead of this call the entire corpus stayed
/// green.
/// That also makes the order testable without a socket: a guard counts how
/// often each thunk ran and in which order, which is a behavioural check,
/// not a source-text one.
///
/// **What this file deliberately does not decide.** Which *key* a table is
/// looked up under. On UDP the source endpoint is the key of the session
/// table (E-104); on a stream transport the connection is the session and
/// the endpoint pair is only a display key (E-116(4)). That difference is
/// real and belongs to the transport, which is why the lookups arrive here
/// as thunks and not as a map. E-122 centralises the **order**, not the
/// storage — an earlier proposal to generalise the whole demux over a
/// transport-neutral source was rejected for exactly this reason.
///
/// No I/O: this module opens no socket and reads no clock it was not given.
library;

import 'dart:typed_data';

import 'package:cleona/core/link/handshake.dart';
import 'package:cleona/core/link/node_keys.dart';

/// The proof that the MAC families have already been computed.
///
/// **A type that only [LinkInboundOrder] can produce** — its
/// constructor is private. Whoever hangs variable work onto a place that
/// demands such a proof can no longer pull it in front: the
/// compiler does not allow it.
///
/// **Why this was necessary, measured.** The header of this file claimed
/// a caller could "not consult a table before the MAC families,
/// because he never gets the chance". For the **lookups** that was true —
/// they are thunks. For **any other** variable work it was not:
/// if you pull `_expire()` (O(table size), runs over the sessions)
/// in front of the call, the entire corpus stays green — 24 smokes, around 730
/// checks, among them this guard and the constant-time guard.
/// Exactly this defect was already present in this tree once (measured 6.2 µs
/// with an empty table against 145 µs with 4 096 entries). A promise in the
/// header sentence that a measurement refutes in minutes is worse than
/// no promise.
final class MacChecked {
  const MacChecked._();
}

/// Which branch an arriving wire unit belongs to.
enum LinkInboundBranch {
  /// The unit carries this node's `init` MAC — it is a handshake flight 1
  /// addressed to us. It is spoken for whatever the responder path makes of
  /// it, including a replay hit, which ends here in silence (E-79).
  init,

  /// No MAC match, and an outbound handshake claimed the unit as its
  /// flight 2.
  flight2,

  /// No MAC match, no pending handshake claimed it, and an established
  /// session did.
  cell,

  /// No MAC match, no pending handshake, no session. Nothing here claims
  /// this unit.
  unclaimed,
}

/// The classification step, in the order E-95/E-79 require.
abstract final class LinkInboundOrder {
  /// Classifies [unit] and returns the branch that claimed it.
  ///
  /// [claimsAsFlight2] and [claimsAsCell] are consulted **only** when no MAC
  /// family matched, and in that order. Neither is called on the [init]
  /// path — that is the point of the thunks.
  ///
  /// **The thunks act, they do not merely test.** Each returns whether its
  /// branch *claimed* the unit, and a branch that claims it has already
  /// consumed it. The two are deliberately not symmetric, and the asymmetry
  /// is load-bearing:
  ///
  /// - [claimsAsFlight2] claims only when the unit really opens as the
  ///   awaited flight 2. A pending handshake that exists but does not open
  ///   this unit returns `false` and lets it through (N-2). The earlier form
  ///   stopped at "a pending exists", and a live pending then blinded the
  ///   established session to the same endpoint — re-dialling a working link
  ///   cost that link its cells until the pending aged out.
  /// - [claimsAsCell] claims whenever a session owns the unit, **including**
  ///   when the sealed cell does not open. A cell that fails its AEAD is
  ///   spoken for and ends in silence; it does not travel further.
  ///
  /// [afterMacCheck] runs once, after the MAC families have been computed
  /// and before any thunk. It is where a caller puts work whose cost depends
  /// on its own state (expiry, eviction); putting it in the caller *before*
  /// this call is the mistake step 2 exists to prevent — and [MacChecked] is
  /// what makes that mistake **not compile** rather than merely discouraged.
  ///
  /// It is **required**, not optional. An optional hook is one a second
  /// receiving path can simply leave out, and then its housekeeping runs
  /// wherever that path happens to put it.
  static LinkInboundBranch classify({
    required NodeKeys keys,
    required Uint8List unit,
    required bool Function() claimsAsFlight2,
    required bool Function() claimsAsCell,
    required void Function(MacChecked) afterMacCheck,
    DateTime? now,
  }) {
    // 1. Constant work, unconditional, before anything else. `acceptsInitMac`
    //    computes both MAC families and returns their disjunction only after
    //    every call has returned (E-95); the guard for that property lives
    //    with the function, not here.
    final bareMac = LinkHandshake.acceptsInitMac(keys, unit, now: now);

    // 2. Variable work — never before the line above.
    afterMacCheck(const MacChecked._());

    // 3. A MAC match ends the unit. No fall-through, not even on a replay
    //    hit: the responder path returns the same silence for a MAC failure
    //    and for a replay, and that sameness is what E-79 requires of the
    //    outside view.
    if (bareMac) return LinkInboundBranch.init;

    // 4. Tables, outbound handshake first.
    if (claimsAsFlight2()) return LinkInboundBranch.flight2;
    if (claimsAsCell()) return LinkInboundBranch.cell;
    return LinkInboundBranch.unclaimed;
  }
}
