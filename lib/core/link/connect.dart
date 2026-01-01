/// Link-layer connect and bind surface — AP-3a stage 3
/// (docs/MIGRATION_V3_TO_V4_0_MYZEL.md §4d.4 points 1/2 and §4d.13.2, decisions
/// E-89, E-95, E-96, E-98, E-99; architecture v4 §2.6a normative, §4.8
/// normative, §4.4 for the tick E-98 is derived against).
///
/// This file is the **surface**, not the wiring: it fixes the signature of
/// the outbound connect path and of the inbound bind contract, the order in
/// which the §4.8 escalation stages are tried, and what happens when a bind
/// fails. It does so **against an injected socket abstraction**
/// ([LinkConnector], [LinkBinder]) and never touches a real socket.
///
/// **Why no real socket here.** Every stage-2 module in this directory is a
/// pure byte function — `cell.dart`, `frame.dart`, `link_mac.dart`,
/// `replay_buffer.dart`, `link_kdf.dart`, `handshake.dart` — and none of
/// them binds, sends or receives anything. Stage 3 keeps that line: the
/// policy this file encodes (which stage next, when to give a stage up,
/// what the bound set is) is exactly the part that must be testable without
/// an operating system. Neither `dart:io` nor — as long as the tree existed —
/// `lib/core/network/` is imported here; the V3 tree has been empty since
/// the CUT of 2026-08-31 (zero files, measured 2026-09-03), the `dart:io`
/// half of the statement still holds. Measured, not enforced: no guard
/// checks it. (Two
/// modules of this directory do import `dart:io`, `node_keys.dart` and
/// `elligator_ffi.dart`; the property that holds for all twelve is the
/// narrower one — none of them opens a socket.)
///
/// **The reason for that line changed, the line did not.** It used to be
/// "connecting this surface to `lib/core/network/transport.dart` is a
/// separate, not-yet-approved step". That step no longer exists: V4 got a
/// node host of its own, and the V3 tree was **deleted** at the lab gate,
/// not rebuilt (CUT, 2026-08-31). The I/O that this file's boundaries stand for lives in
/// `lib/core/link_io/` (E-100). What keeps `dart:io` out of here is now
/// simply testability — policy that needs no operating system should not
/// acquire one.
///
/// **What this file deliberately does NOT contain:**
///
/// - **No handshake.** [LinkConnector.attempt] is the I/O boundary and is
///   also where the two flights of §2.6 run; this file only learns whether
///   the attempt produced contact, was refused, or stayed silent. Pulling
///   `LinkHandshake` in here would drag libsodium and liboqs into a policy
///   module and into every test of it.
/// - **No disguise path and no `MAC_hdr` (E-95, E-62/E-75).** [Disguise]
///   has exactly one value today, `bare`, so there is no second MAC family
///   to verify and nothing to wrap. What is built here must be able to
///   *take* the second family later without changing shape — see
///   [bind] and [survivingBinds] for where that shows.
/// - **No failure counter, in any form (§2.6a "What must not happen",
///   §4.8).** A finished cascade run leaves **nothing** behind: [connect]
///   writes to [ConnectState] only on success, and [ConnectState] itself
///   has no `recordFailure`. There is no field, static or otherwise, that
///   survives a run — the guard in
///   `test/smoke/smoke_link_transport_selector.dart` scans this whole
///   directory for one, and `test/smoke/smoke_link_connect.dart` checks the
///   same thing behaviourally.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:cleona/core/link/connect_state.dart';
import 'package:cleona/core/link/transport_selector.dart';

/// Where a log line from this layer goes.
///
/// Injected rather than imported for the same reason the sockets are: the
/// house logger (`lib/core/log/clogger.dart`) writes files and starts a
/// periodic timer, which is I/O and process lifetime — neither belongs in a
/// policy module. The wiring step passes an adapter.
typedef LinkLogSink = void Function(String message);

/// The §4.8 stage timeout: how long one cascade stage is given to answer
/// before it counts as **silently failed** and the run escalates (E-98,
/// decided 2026-08-19; architecture v4 §4.8 normative, §4.4 for the tick).
///
/// **Where 1.5 s comes from.** §4.8 fixes the property, not the number: "a
/// **short fixed timeout** applies, well below the tick duration of the
/// budget class, so a full run completes within one tick". The binding
/// budget class is **Carrier**, whose epoch tick is **~10 s** (§4.4) — the
/// shorter of the two classes that drive a cascade; the Harvester's ~5 min
/// burst is not the constraint. A full run is four stages ([TransportStage]
/// has four values), and **only silently failing stages cost the timeout**:
/// an explicit refusal ([LinkRefused]) escalates at once, without waiting.
/// The worst case is therefore 4 × 1.5 s = **6 s**, 60 % of the tick — the
/// §4.8 promise "a full run completes within one tick" holds with reserve.
///
/// **Why not shorter.** 1.0 s would cut off slow mobile paths whose round
/// trip reaches into the second, and would escalate them needlessly to
/// `tcp443` and `icmpKnock` — stages that cost privileges and visibility (a
/// 443 door on the far side, and an ICMP knock that is recognisable as such
/// on the wire).
///
/// **This is a tuning constant, not wire format.** Nothing on the wire
/// depends on it and two peers need not agree on it. That is why
/// [Link.connect] keeps it as an ordinary parameter that merely *defaults*
/// to this value: a caller with a reason may override it, and the guards
/// run the cascade at 20 ms so a silent stage does not cost them a second
/// and a half.
const Duration kLinkStageTimeout = Duration(milliseconds: 1500);

/// A connect target: host and port, nothing else.
///
/// **Why not `InternetAddress` and why not `PeerAddress`
/// (`lib/core/network/peer_info.dart`, deleted with the CUT of
/// 2026-08-31 — the comparison is historic, the rule it states is not).**
/// `InternetAddress` lives in
/// `dart:io` and would break the I/O-free line of this directory for the
/// sake of a value type. `PeerAddress` is a *mutable V3 scoring record* —
/// score, success/failure counters, backoff state — i.e. exactly the
/// accumulated per-address failure history §4.8 rules out for this axis; it
/// also carries `dart:io`. A minimal immutable pair is what the surface
/// needs.
///
/// [key] is the entry key of [ConnectState], whose contract documents the
/// composition as `"$address:$port"` and treats it as opaque.
final class LinkEndpoint {
  final String host;
  final int port;

  const LinkEndpoint(this.host, this.port);

  /// The [ConnectState] entry key for this target (§2.6a "Key is the
  /// destination address", E-89).
  String get key => '$host:$port';

  @override
  bool operator ==(Object other) =>
      other is LinkEndpoint && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);

  @override
  String toString() => 'LinkEndpoint($host:$port)';
}

/// An established link, as far as this layer is concerned: an opaque handle
/// that knows which transport carries it and can be closed.
///
/// The byte API was absent until both questions it would otherwise have
/// answered by accident were settled. Whoever writes `send` picks a
/// direction key — settled by E-107: `LinkSession` hands out
/// `sendKey`/`recvKey` and no consumer ever chooses between `init` and
/// `resp`. Whoever writes the receive side picks how a datagram finds its
/// session — settled by E-104: the source endpoint is the key, and the
/// lookup runs **after** the MAC families, not before them.
///
/// **It deals in inner frames, not in sealed cells.** [send] takes exactly
/// `kCellPlaintextSize` bytes and seals them; [inbound] carries opened
/// inner frames. Sealing and opening therefore happen in **one** place per
/// link, which is what keeps the direction keys out of every caller's
/// reach — the same reason E-107 removed the raw fields from the session.
///
/// This interface is no wire format: it passes an opaque unit through, and
/// the AP-3a freeze does not run on it.
abstract interface class LinkChannel {
  /// The transport this channel actually runs on — the product value
  /// `(stage, disguise)` of §2.6a point 1, not just the stage.
  LinkTransport get transport;

  /// Seals [inner] under this link's send key and puts it on the wire.
  ///
  /// [inner] must be exactly `kCellPlaintextSize` bytes — the cell is
  /// constant-size by construction (§2.2), so a short frame stream is
  /// padded by `buildInner`, never by this call.
  void send(Uint8List inner);

  /// The key with which the DELIVERY LAYER works on this link.
  ///
  /// A domain-separated child of the `link_key` (`LinkKdf.infoDelivery`),
  /// not the `link_key` itself — that stays in the link layer.
  Uint8List get deliveryKey;

  /// The verified position of the other end, or `null` if it stayed
  /// anonymous (decision C, 2026-08-22).
  ///
  /// It is set if the other end has identified itself and we already had
  /// its entry record. The authentication is implicit: the key was formed
  /// against this position. Whoever lied cannot open anything we send —
  /// the attribution is therefore usable immediately, even before the
  /// first cell has arrived.
  Uint8List? get peerPosition;

  /// Inner frame streams of the cells that arrived on this link, opened.
  ///
  /// A cell that does not authenticate never reaches here: it carries no
  /// information and is dropped in silence (§2.6 posture). The absence of
  /// an event is the only thing a peer learns.
  Stream<Uint8List> get inbound;

  Future<void> close();
}

/// The result of one attempt of one cascade stage, as reported by the
/// injected connector.
///
/// The third case of §4.8 — the network discards **silently** — is
/// deliberately *not* a member here: silence is the absence of any report,
/// and it is expressed by a future that has not completed when
/// [connect]'s `stageTimeout` elapses. A connector that invented a
/// "silent" answer would be claiming knowledge it cannot have.
sealed class LinkAttempt {
  const LinkAttempt();
}

/// The counterpart answered and the link is up.
final class LinkEstablished extends LinkAttempt {
  final LinkChannel channel;
  const LinkEstablished(this.channel);
}

/// The operating system refused explicitly — `ECONNREFUSED`, an immediate
/// RST, ICMP "administratively prohibited" (§4.8 "When a stage is given
/// up"). This escalates **at once**, without waiting out the timeout.
final class LinkRefused extends LinkAttempt {
  /// Free text for the log/diagnostic path only. Nothing branches on it.
  final String reason;
  const LinkRefused(this.reason);
}

/// The injected outbound I/O boundary: one attempt of one transport against
/// one address.
///
/// The implementation performs the actual socket work **and** the §2.6
/// handshake, and reports only the outcome. It must impose **no timeout of
/// its own**: the stage timeout is [connect]'s parameter (§4.8), and a
/// second timeout inside the connector would silently take that decision
/// away from the layer that owns it.
abstract interface class LinkConnector {
  Future<LinkAttempt> attempt(LinkEndpoint target, LinkTransport transport);
}

/// How one stage of a cascade run ended. Diagnostic only — no caller
/// branches on it, and nothing is accumulated from it across runs.
enum LinkAttemptOutcome {
  /// Contact. The run ends here.
  established,

  /// Explicit OS refusal — escalate immediately (§4.8).
  refused,

  /// No answer within `stageTimeout` — escalate (§4.8).
  silent,
}

/// One line of the run record: which stage was tried, how it ended.
final class LinkStageAttempt {
  final TransportStage stage;
  final LinkAttemptOutcome outcome;

  const LinkStageAttempt(this.stage, this.outcome);

  @override
  String toString() => 'LinkStageAttempt(${stage.name}, ${outcome.name})';
}

/// The outcome of one full cascade run (§4.8).
final class LinkConnectResult {
  /// The established channel, or `null` if the run ended without contact.
  final LinkChannel? channel;

  /// The transport that carried the successful attempt, or `null`.
  final LinkTransport? transport;

  /// Every stage tried, in the order it was tried. Each stage appears at
  /// most **once** — §4.8, "Each stage is attempted once per cascade run".
  final List<LinkStageAttempt> attempts;

  const LinkConnectResult({
    required this.channel,
    required this.transport,
    required this.attempts,
  });

  bool get established => channel != null;
}

/// The inbound counterpart of [LinkChannel]: a bound listener for one
/// disguise. Opaque here for the same reason.
abstract interface class LinkBinding {
  Disguise get disguise;

  Future<void> close();
}

/// The injected inbound I/O boundary.
///
/// **"Bind" here is the listener contract, not necessarily a socket.**
/// §2.6a (E-95) rules that on UDP a disguise shares **one socket** with the
/// bare path of necessity — a second port is foreclosed by E-64 and a
/// second `SO_REUSEADDR` socket on the same port is documented broken —
/// so for such a disguise this call is a demultiplex registration on the
/// listener that already exists, not a second `bind(2)`. The transports
/// that do own a listener (the node's own port, the 443 door of §4.8) are
/// the ones that can fail the way E-96 describes.
///
/// **Failure is a thrown exception, not a return value** — that is how the
/// real API behaves (`RawDatagramSocket.bind` throws `SocketException` on
/// `EADDRINUSE`, and the 443 door fails the same way when the kernel
/// redirect the installer sets up is absent). [bind] catches it; see E-96
/// there.
abstract interface class LinkBinder {
  Future<LinkBinding> bindDisguise(Disguise disguise);
}

/// The result of one [bind] call.
final class LinkBindResult {
  /// What the caller asked for, unchanged.
  final Set<Disguise> requested;

  /// What was actually attempted: [requested] plus `bare`, always
  /// (§2.6a point 2, "the invariant is that `bare` is part of the bound
  /// set even for `bind({})`"). This set is a **contract**, independent of
  /// what the operating system then allows.
  final Set<Disguise> attempted;

  /// What is bound now — [attempted] minus everything that failed (E-96).
  final Set<Disguise> bound;

  /// The live listeners, keyed by disguise.
  final Map<Disguise, LinkBinding> bindings;

  /// Why a member of [attempted] is missing from [bound]. Empty on a clean
  /// start. Every entry here produced exactly one log line (E-96). The one
  /// failure that never shows up in this map is `bare`'s: it throws
  /// [LinkBareBindFailure] instead of returning a result at all (E-99).
  final Map<Disguise, Object> failures;

  const LinkBindResult({
    required this.requested,
    required this.attempted,
    required this.bound,
    required this.bindings,
    required this.failures,
  });
}

/// The bare listener itself could not be bound — thrown by [bind], and by
/// nothing else (E-99, decided 2026-08-19).
///
/// **Why this fails the start at all, when E-96 does not.** E-96 rules that
/// a transport which cannot bind falls away silently, and it decides that
/// way because a node that loses a *disguise* loses an addition and stays
/// fully reachable on the bare path (§2.6a point 4). That consideration
/// does not carry over to `bare` itself: a node without a bare listener has
/// no data port and is **deaf**. A daemon that runs on quietly without one
/// is the failure nobody notices until messages stop arriving — so the
/// start fails loudly instead.
///
/// **Why its own type and not a generic `Exception`.** The caller has to be
/// able to tell "the node cannot listen" apart from every other error that
/// can come out of a start sequence, without matching on message text. A
/// distinct type is the only form of that a `catch` clause can use.
final class LinkBareBindFailure implements Exception {
  /// What the binder threw for `bare` — a `SocketException` (`EADDRINUSE`)
  /// in the real implementation.
  final Object cause;

  const LinkBareBindFailure(this.cause);

  @override
  String toString() =>
      'LinkBareBindFailure: the bare listener could not be bound — the node '
      'would have no data port and be deaf, so the start fails (E-99). '
      'Cause: $cause';
}

/// Which bind failure is fatal (E-99) and which one merely falls away
/// (E-96): the [bare] member is, every other member is not.
///
/// **Why generic — the same reason [survivingBinds] is.** The property that
/// has to be provable is *"only the bare member is fatal"*, and its second
/// half — a failing member that is **not** `bare` does not fail the start —
/// cannot be exercised on [Disguise], which has exactly one value today
/// (E-89/E-62/E-75): a `Set<Disguise>` can never hold both a failing
/// disguise and a healthy `bare`. Written over an arbitrary element type,
/// the rule can be checked with a two-member set now, and the second
/// disguise family (E-95) arrives later without this function changing.
bool bindFailureIsFatal<T>(T failed, T bare) => failed == bare;

/// The §2.6a point 2 bind invariant as a pure function: `bare` is in the
/// set that gets bound, whatever the caller asked for — including
/// `bind({})`.
///
/// Split out of [bind] so the guard
/// (`test/smoke/smoke_link_bind_invariant.dart`) can check the invariant
/// itself rather than only its effect through an injected binder.
Set<Disguise> effectiveBindSet(Set<Disguise> requested) => <Disguise>{
      // First, so iteration order below starts with the bare transport —
      // §2.6a point 4, "Default is bare".
      Disguise.bare,
      ...requested,
    };

/// The E-96 rule, as a set operation: what could not bind drops out, and
/// **everything else is untouched**.
///
/// **Why generic.** The property that matters is *isolation* — one failing
/// member must not take another one down — and that cannot be exercised on
/// [Disguise], which has exactly one value today (E-89/E-62/E-75); a set
/// over it can never hold two members. Writing the rule as a set difference
/// over an arbitrary element type lets the guard prove the isolation with a
/// two-member set today, and lets the second disguise family arrive later
/// (E-95, "the structure must be able to take it without changing") without
/// this function being rewritten.
Set<T> survivingBinds<T>(Set<T> attempted, Set<T> failed) =>
    attempted.difference(failed);

/// The link layer's connect and bind surface (§2.6a).
///
/// Both entry points are named as the architecture names them. They are
/// static because there is deliberately **no object to hold state**: an
/// instance would be a place for the "current transport" that §2.6a
/// forbids.
abstract final class Link {
  /// One cascade run against [target] (§4.8), starting from [transport].
  ///
  /// **The transport is an argument (E-89, §2.6a point 1), never a global
  /// mode.** It is the product value `(stage, disguise)`; the cascade
  /// escalates the **stage** and keeps the **disguise** fixed for the whole
  /// run. That is the axis separation of §4d.4 point 4 made operational:
  /// nothing in this function can move the disguise axis, so no single
  /// driver can ever feed both.
  ///
  /// **Order of the run.** [transport]'s stage is tried first, then every
  /// remaining stage in the §4.8 cascade order — each stage exactly once
  /// ("Each stage is attempted once per cascade run"). The order itself is
  /// not restated here; it is walked out of [nextStage], which is its
  /// single source of truth.
  ///
  /// **When a stage is given up (§4.8).** A [LinkRefused] escalates at
  /// once. Otherwise the attempt is given [stageTimeout]; if it has not
  /// answered by then the stage counts as silently failed and the run
  /// escalates.
  ///
  /// **[stageTimeout] defaults to [kLinkStageTimeout] = 1.5 s (E-98).**
  /// It used to be a required parameter without a default, and the reason
  /// given for that was explicit: §4.8 named the property but no number, so
  /// picking one here would have been an implementation deciding a
  /// normative figure. **E-98 names the number**, so that reason has
  /// expired — keeping the parameter required would be keeping a
  /// construction whose stated justification no longer exists, and would
  /// leave every future call site free to type a literal of its own instead
  /// of inheriting the one value that was derived against the tick. The
  /// derivation lives on [kLinkStageTimeout]. It stays an ordinary
  /// parameter rather than becoming a hard-wired constant because the value
  /// is a tuning constant, not wire format (see there), and the guards must
  /// be able to run the cascade at 20 ms.
  ///
  /// **[state] is a hint, never a counter.** When a [ConnectState] is
  /// supplied and holds a live entry for [target], the remembered stage is
  /// tried **first** and the rest of the cascade follows (§2.6a, "on a hit
  /// the remembered stage is tried first", E-89). A successful attempt is
  /// recorded. A failed run records **nothing** — there is no path in this
  /// function that writes on failure.
  ///
  /// *Open, not decided here:* when the caller pins a stage in [transport]
  /// **and** [state] holds a different one, this implementation lets the
  /// remembered stage win, because that is the literal wording of the hit
  /// behaviour; a caller that wants to pin a stage passes no [state]. The
  /// precedence between the two is written nowhere.
  static Future<LinkConnectResult> connect({
    required LinkEndpoint target,
    required LinkTransport transport,
    required LinkConnector connector,
    Duration stageTimeout = kLinkStageTimeout,
    ConnectState? state,
    DateTime? now,
  }) async {
    final hinted = state?.preferredStage(target.key, now: now);
    final first = (hinted != null &&
            hinted >= 0 &&
            hinted < TransportStage.values.length)
        ? TransportStage.values[hinted]
        : transport.stage;

    final attempts = <LinkStageAttempt>[];

    for (final stage in _runOrder(first)) {
      // The disguise never moves — only the stage does (E-89, §4d.4 point 4).
      final candidate = LinkTransport(stage, transport.disguise);

      LinkAttempt? result;
      try {
        result = await connector
            .attempt(target, candidate)
            // Widened to nullable so `null` can carry "silent": silence is
            // the absence of an answer, so it is timed here and not
            // reported by the connector (§4.8). A late answer after this
            // point is dropped by `Future.timeout` itself.
            .then<LinkAttempt?>((a) => a)
            .timeout(stageTimeout, onTimeout: () => null);
      } on TimeoutException {
        // Belt and braces: a connector that surfaces its own
        // TimeoutException must not turn a silent stage into a thrown run.
        result = null;
      }

      switch (result) {
        case LinkEstablished(:final channel):
          attempts.add(
              LinkStageAttempt(stage, LinkAttemptOutcome.established));
          state?.recordSuccess(target.key, stage.index, now: now);
          return LinkConnectResult(
            channel: channel,
            transport: candidate,
            attempts: attempts,
          );
        case LinkRefused():
          // Escalate at once — no wait (§4.8).
          attempts.add(LinkStageAttempt(stage, LinkAttemptOutcome.refused));
        case null:
          attempts.add(LinkStageAttempt(stage, LinkAttemptOutcome.silent));
      }
    }

    // After the last stage (`icmpKnock`) the run ends "without leaving
    // state"; the next breath starts again at `udpOwnPort` (§4.8, §4d.7 C).
    // Nothing is written here — not a counter, not a timestamp, not a
    // "this address only takes 443" note.
    return LinkConnectResult(
      channel: null,
      transport: null,
      attempts: attempts,
    );
  }

  /// Binds the inbound side (§2.6a point 2, E-89; failure behaviour E-96).
  ///
  /// The signature is `bind(Set<Disguise>)` as the architecture fixes it.
  /// The set that is actually bound is [effectiveBindSet] of [disguises] —
  /// `bare` is always in it, including for `bind({})`.
  ///
  /// **E-96 — a transport that cannot bind falls away silently.** A bind
  /// failure is caught, recorded in [LinkBindResult.failures], written to
  /// [log] as exactly one line, and the loop continues. Start does **not**
  /// fail and nothing is rethrown. The log line is the whole point of the
  /// decision: without it a disguise that never binds is invisible for the
  /// lifetime of the process.
  ///
  /// **E-99 — unless the member that failed is `bare` itself: then the
  /// start fails.** This is the one exception to the paragraph above, and
  /// it is an exception because E-96's own reasoning stops here: a node
  /// that loses a disguise loses an addition, a node without `bare` is
  /// deaf. [LinkBareBindFailure] is thrown, with the binder's error as its
  /// cause, and the caller can tell that case apart by type.
  ///
  /// **The log line is written first, then the throw.** E-96's requirement
  /// "the failure is logged" holds for *every* failure, and for the fatal
  /// one all the more: the line is what an operator finds afterwards. The
  /// entry in [LinkBindResult.failures] is not what survives here — the
  /// result object is never returned on this path — which is exactly why
  /// the log call must not be skipped.
  ///
  /// *Considered and NOT chosen (E-99):* drawing a new port and binding
  /// again. A redraw would change the address under which contacts look for
  /// this node, and that touches §4.5. (This used to be justified by
  /// `drawDataPort` deriving the port "deterministically from the
  /// identity". It does not: `lib/core/link/data_port.dart` draws it with
  /// `Random().nextInt(55000)`, once, and persists the result. The
  /// conclusion holds — a redraw moves the address either way — the stated
  /// reason did not.)
  /// That is expressly not decided, and it is therefore not built.
  ///
  /// **[log] is required, not optional.** An optional sink is a sink that
  /// gets forgotten, and a forgotten sink turns E-96's "is logged" into
  /// "is swallowed" — the exact state E-96 was decided against.
  ///
  /// **[LinkBindResult.failures] is data, not error propagation.** E-96
  /// rejects "letting the start fail, and propagating the error upward to
  /// the caller", because both make an **optional wrapper** a precondition
  /// for the node running at all. That objection is about optional
  /// transports; it does not reach the bare path, which is not optional and
  /// not a wrapper. So for every member except `bare` the map is the whole
  /// story: nothing is returned as an error channel and no caller is forced
  /// to branch — the map carries the same information as the log line, in a
  /// form a guard can read.
  ///
  /// **The loop has no early exit, and the bound set is formed after it
  /// (E-95 shape).** Every member of the effective set is attempted,
  /// independently of what any other member did, and the result is computed
  /// once, at the end, by [survivingBinds]. Today that is a formality —
  /// there is one disguise. It is written this way because the receive-side
  /// counterpart of E-95 ("both MAC families are checked unconditionally,
  /// independently, and the disjunction stands after all calls") lands in
  /// exactly this loop when the second family exists, and it must not
  /// require the structure to change then.
  ///
  /// Throws [LinkBareBindFailure], and only that, when `bare` cannot bind.
  static Future<LinkBindResult> bind(
    Set<Disguise> disguises, {
    required LinkBinder binder,
    required LinkLogSink log,
  }) async {
    final attempted = effectiveBindSet(disguises);
    final bindings = <Disguise, LinkBinding>{};
    final failures = <Disguise, Object>{};

    for (final disguise in attempted) {
      try {
        bindings[disguise] = await binder.bindDisguise(disguise);
      } catch (e) {
        failures[disguise] = e;
        if (bindFailureIsFatal(disguise, Disguise.bare)) {
          // Logged BEFORE the throw: E-96's "the failure is logged" holds
          // for every failure, and this result object never reaches a
          // caller, so the line is the only record that survives.
          log('link/bind: the bare listener could not be bound — the node '
              'would have no data port and be deaf, so the start fails '
              '(E-99) — $e');
          // No listener is leaked by leaving here: `bare` is the FIRST
          // member of `effectiveBindSet`, so nothing else has been bound
          // yet. Should that order ever change, closing what is already in
          // `bindings` becomes an open question — it is not one today.
          throw LinkBareBindFailure(e);
        }
        log('link/bind: disguise "${disguise.name}" could not bind and was '
            'dropped (E-96) — $e');
      }
    }

    return LinkBindResult(
      requested: disguises,
      attempted: attempted,
      bound: survivingBinds(attempted, failures.keys.toSet()),
      bindings: bindings,
      failures: failures,
    );
  }

  /// The stages of one run, [first] followed by every other stage in the
  /// §4.8 cascade order, each exactly once.
  ///
  /// The order is **walked out of [nextStage]**, never restated: a second
  /// copy of the cascade order in this file could drift from the one the
  /// selector guard pins.
  static List<TransportStage> _runOrder(TransportStage first) {
    final order = <TransportStage>[first];
    TransportStage? s = TransportStage.values.first;
    while (s != null) {
      if (s != first) order.add(s);
      s = nextStage(s);
    }
    return order;
  }
}
