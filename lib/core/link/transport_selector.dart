/// Link transport selector — the `Transport(stage, disguise)` product type
/// of §2.6a ("the connect path takes the transport as an argument") and its
/// escalation-cascade order (architecture v4 §4.8; AP-3a step 3,
/// docs/MIGRATION_V3_TO_V4_0_MYZEL.md §4d.13.2, decision E-89).
///
/// **Naming: `LinkTransport`, not `Transport`.** `lib/core/network/transport.dart`
/// defined a class `Transport` — the V3 UDP/TLS socket layer — until the CUT
/// of 2026-08-31 removed it (zero files under `lib/core/network/`, measured
/// 2026-09-03). The collision is gone; the name stays, because renaming it
/// back would reopen the finding for no gain. §4d.13.2
/// names that exact collision as a finding ("the same collision … as the
/// Dart class `Transport` against the §2.6a selector") and requires the two to
/// be resolved with **separate names**, not by inheriting the clash into the
/// V4 code. This type is the V4 connect-path selector; the V3 socket class is
/// untouched and keeps its name.
///
/// **Two axes, not one (E-89).** §2.6a and §4.8 both use the word
/// "transport" for different things: §2.6a means the **disguise** axis (a
/// disguised transport standing *alongside* the bare one, never replacing
/// it — K16-6), §4.8 means the **escalation** axis (which address/port/
/// protocol combination is tried next for one address). Mixing both into one
/// enumeration would violate the axis separation that E-62
/// and §4d.4 point 4 require, and — the actual hazard — would let a single
/// counter drive both axes at once, rebuilding exactly the V3 escalation
/// ladder (UDP → fragmented → TLS) that V4 discarded together with the retry
/// machinery (§1.1 Axiom 2, §2.6a "What must not happen"). [LinkTransport]
/// is therefore a **product type** of two independent enums, [TransportStage]
/// and [Disguise] — see the type doc below for why a product type and not
/// two loose parameters.
library;

/// The escalation axis (architecture v4 §4.8, "Transport escalation per
/// address", normative E-64), in the order the connect-path cascade tries
/// them for a single address. This is **not** the disguise axis — see
/// [Disguise] — and it does not, by itself, choose a disguise.
///
/// The cascade never mixes UDP-disguise-capability into this ordering, and
/// it must not be driven by an accumulating failure counter (§4.8, "an
/// accumulating failure counter would rebuild exactly the mechanism §2.6a
/// forbids"; the same prohibition again in §2.6a "What must not happen").
/// Each stage is tried once per cascade run, and after the last stage the
/// run ends **without leaving state** (§4.8, decided 2026-08-18) — the next
/// run starts again at [udpOwnPort]. [nextStage] below reflects only the
/// fixed order, never a retry count.
enum TransportStage {
  /// The node's own (random, 10000-64999) port over UDP — the default,
  /// taken from the entry record (§4.8, stage `udpOwnPort`). This is
  /// [bareDefault]'s stage: a node that knows nothing about transports
  /// behaves exactly as this value alone.
  udpOwnPort,

  /// The node's own port over TCP (§4.8, stage `tcpOwnPort`, E-65) — for
  /// networks that block UDP outbound but permit arbitrary TCP ports. The
  /// node opens its own listener there (§2.1a; E-116, E-100) — the V3
  /// listener this stage was once said to ride along on lives in a tree
  /// the lab gate deletes. The first byte on the wire distinguishes the
  /// link handshake from HTTP. Needs no door on the counterpart — two
  /// ordinary nodes suffice.
  tcpOwnPort,

  /// TCP on port 443 of the same address (§4.8, stage `tcp443`) — for the
  /// port-filter case, through the platform's configured proxy where one is
  /// mandatory (E-66). 443 is a **property** a reachable node may have, not
  /// a second service (§4.8 "443 doors — a property, not a role", E-64);
  /// the entry record carries no field announcing it, so this stage finds a
  /// 443 door only by trying it.
  tcp443,

  /// ICMP echo as a last resort before switching the network interface
  /// (§4.8, stage `icmpKnock`). A **bounded substitute channel**, not an L4
  /// protocol for the constant cell stream of §4.3 — throughput and DPI
  /// visibility rule that out (§2.1a, §4.8 "ICMP, honestly bounded"). It
  /// does carry the §2.6 link handshake and, while the port filter holds,
  /// the cells that follow; its role is the outbound door-connect out of a
  /// network that drops all ports but passes ping (E-64, C-1).
  icmpKnock,
}

/// The disguise axis (architecture v4 §2.6a, decision K16-6/E-62): whether
/// the wire shape of a connection on a given [TransportStage] is the bare
/// Cleona cell stream or dressed up as something else (QUIC-shaped,
/// DTLS-shaped, real TLS 1.3 on 443).
///
/// **Deliberately one-element today, and that is the point (E-89, E-62,
/// E-75).** AP-3 freezes the link layer's wire format; §2.6a exists so that
/// a place to plug in a second transport does not have to be retrofitted
/// later without a second wire format and a mixed network. Only that
/// placeholder is deadline-bound — "only the parameterization is
/// fristgebunden" (E-62). The disguise itself stays deliberately
/// unspecified: which concrete disguise to build, who runs its far side,
/// and how it clears the handshake binding of E-69/E-90/E-91 are all still
/// open (§4d.13.3, §4d.13.4). **Do not "clean up" this enum to a typedef or
/// a bare `bool` because it only has one value today** — the single element
/// is the documented state of an intentionally open axis, not an oversight.
/// Grep for `Disguise.bare` before adding a second value; the guard test in
/// `test/smoke/smoke_link_transport_selector.dart` deliberately breaks the
/// moment a second value lands, precisely so its removal is noticed and the
/// dependent guards (§4d.4) are pulled forward at the same time.
enum Disguise {
  /// The undisguised Cleona cell stream — same 1200-B cells (§2.2), same
  /// `L_node`-bound handshake (§2.6), same link key as always. "A transport
  /// is a wrapper, not a second protocol" (§2.6a point 3). This is the only
  /// value that exists, and per §2.6a point 4 it is also the default: a
  /// peer offering only `bare` stays fully reachable.
  bare,
}

/// A transport is a product of the two axes above — the value the connect
/// path takes "as an argument" (§2.6a point 1).
///
/// **Why a product type and not two loose parameters
/// (`connect(addr, stage, disguise)`, option A2 in §4d.13.2).** §4d.13.2
/// weighs three shapes for the same requirement and recommends option A3,
/// this one: the axis separation the architecture demands (E-62, §4d.4
/// point 4) must live **in the type**, not in caller discipline. Two loose
/// parameters keep the axes apart only as long as every call site is
/// written correctly; a product type makes a caller that tries to fold both
/// axes into one shared counter or one shared enum a compile error instead
/// of a code-review finding. Bundling the two fields here keeps the
/// single-argument shape of §2.6a point 1 while still holding the guarantee
/// in the type system rather than in discipline.
final class LinkTransport {
  /// The escalation stage this transport runs on (§4.8).
  final TransportStage stage;

  /// The disguise this transport wears on that stage (§2.6a).
  final Disguise disguise;

  const LinkTransport(this.stage, this.disguise);

  /// The default transport (§2.6a point 4, "Default is bare"): the node's
  /// own UDP port, undisguised. A node that knows nothing about transports
  /// behaves exactly as this value alone describes.
  static const LinkTransport bareDefault =
      LinkTransport(TransportStage.udpOwnPort, Disguise.bare);

  @override
  bool operator ==(Object other) =>
      other is LinkTransport &&
      other.stage == stage &&
      other.disguise == disguise;

  @override
  int get hashCode => Object.hash(stage, disguise);

  @override
  String toString() => 'LinkTransport(${stage.name}, ${disguise.name})';
}

/// The fixed cascade order of §4.8, one step at a time: the stage tried
/// immediately after [current], or `null` after [TransportStage.icmpKnock]
/// (the last stage — §4.8: after `icmpKnock` the run ends "without leaving
/// state").
///
/// **This is order, not state.** It answers "what comes next in the fixed
/// list", nothing else. It takes no failure count, no history, and no
/// mutable selector state, and it must never be given any: §4.8 rules that
/// "an accumulating failure counter would rebuild exactly the mechanism
/// §2.6a forbids", and §2.6a itself forbids the same thing for the disguise
/// axis ("the choice must not come from a failure counter"). The caller
/// that drives a cascade run is the one that owns *whether* to advance
/// (timeout, explicit OS refusal, §4.8 "When a stage is given up"); this
/// function only ever answers *to what*, and it answers the same way every
/// time for the same [current] — no instance, no field, nothing retained
/// between calls.
TransportStage? nextStage(TransportStage current) {
  const order = [
    TransportStage.udpOwnPort,
    TransportStage.tcpOwnPort,
    TransportStage.tcp443,
    TransportStage.icmpKnock,
  ];
  final i = order.indexOf(current);
  final next = i + 1;
  return next < order.length ? order[next] : null;
}
