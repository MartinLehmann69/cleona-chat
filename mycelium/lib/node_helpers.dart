import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cleona/core/config/network_channel.dart'
    show NetworkChannel, activeNetworkChannel;
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:mycelium/invitation.dart' as inv;
import 'package:mycelium/identity.dart';
import 'package:mycelium/wire.dart';
import 'package:mycelium/shell.dart';
import 'package:mycelium/cover_stream.dart' as cover;
import 'package:mycelium/card.dart';
import 'package:mycelium/ladder.dart';
import 'package:mycelium/node_amendment.dart';
import 'package:mycelium/node_invitation.dart';
import 'package:mycelium/node.dart';
import 'package:mycelium/board_proof.dart';
import 'package:mycelium/board_node.dart';
import 'package:mycelium/kinds.dart' as kinds;

/// `ownLanAddress` and `ownIpv4` were in this file until S390. They
/// are still offered here so that the callers remain unchanged;
/// the new place is `own_address.dart`.
export 'package:mycelium/own_address.dart';

/// Small helpers of the node — moved out because they have nothing to do with
/// its wiring and the line budget would otherwise break
/// precisely because of them.
/// Private ranges per RFC 1918 — whoever comes from there did not come via
/// the open network.
bool isPrivate(InternetAddress a) {
  final b = a.rawAddress;
  // ── S390: IPv6 must NOT fall through here any longer ──────────────────
  //
  // Until here stood `if (b.length != 4) return false;` — every
  // IPv6 address thus counted as „not private", even `::1` and `fe80::1`.
  // As long as the wire was IPv4-only, nobody could trigger that. With the
  // second socket (§11.1) and the typed `0x41` answer, one could: the
  // three callers of this function are the gates before `publicAddress`
  // (`node_outside.dart`), before the public field of the card
  // (`mailbox_invitation.dart`) and before the Nostr entry
  // (`host_outside.dart`). A link-local address would have landed there as a
  // PUBLIC one — and an issued card is valid for 90 days.
  //
  // Owner decision 16.09.2026: „link-local as public makes no
  // sense! Do not publish!" — and: not into Nostr, not into the
  // public node search, to neighbours in the same network very much so (that
  // is decided by `outTheSegment`, not this function).
  //
  // INTERIM STATE, deliberately named so: this function still answers the question
  // „reachable from the open network?" only via its negation
  // and is still wrongly named. On 16.09. the owner decided
  // that the address classification moves to mycelium and in doing so becomes
  // `weltweitErreichbar` (`berichte/S390-VORLAGE-ADRESSKLASSEN.md`).
  // Until then this block closes the window instead of leaving it open.
  if (b.length == 16) {
    if (a.isLoopback) return true; //             ::1
    if (b.every((x) => x == 0)) return true; //   :: (unspezifiziert)
    if (b[0] == 0xFF) return true; //             ff00::/8  Multicast
    if (b[0] == 0xFE && (b[1] & 0xC0) == 0x80) return true; // fe80::/10
    if ((b[0] & 0xFE) == 0xFC) return true; //    fc00::/7  ULA
    if (b[0] == 0x20 && b[1] == 0x01 && b[2] == 0x0D && b[3] == 0xB8) {
      return true; //                             2001:db8::/32  Doku
    }
    return false; // global IPv6 — and exactly that is to be published
  }
  if (b.length != 4) return true; // neither 4 nor 16: nothing that holds
  if (b[0] == 10) return true;
  if (b[0] == 192 && b[1] == 168) return true;
  if (b[0] == 172 && b[1] >= 16 && b[1] <= 31) return true;
  if (b[0] == 127) return true;
  return false;
}

Uint8List hashFrom(Uint8List x) => SodiumFFI().sha256(x);

Uint8List roll(int n) {
  final r = Random.secure();
  final b = Uint8List(n);
  for (var i = 0; i < n; i++) {
    b[i] = r.nextInt(256);
  }
  return b;
}

String hexFrom(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

/// The first [n] characters of [s] for a report — without throwing if
/// [s] is shorter. For EVERY value that can come from the wire (BF-1, S388:
/// `substring(0, 8)` on a foreign identifier ended the process).
String shortFrom(String s, [int n = 8]) => s.length <= n ? s : s.substring(0, n);

/// The channel byte of the invitation card for the network channel on which this
/// node runs (V4.2 §15.2: `0x00` live, `0x01` beta).
///
/// ONE place and the same source as the identifier (`address.dart`,
/// `kIdentityDomainBytes`): `activeNetworkChannel`. Issuing ([cardFor])
/// and redeeming (`MailboxInvitation.join`) both read here. Until S387
/// mycelium knew no channel: every card carried live, and only live
/// was read — on beta, therefore, no card of the app was redeemable.
int get cardChannel => activeNetworkChannel == NetworkChannel.live
    ? Card.channelLive
    : Card.channelBeta;


/// Builds the invitation card of an identity.
///
/// Lives here and not in the node: a card arises from the own
/// keys and the own address — it needs no network, no
/// socket and no wiring (§12.4). Exactly for that reason it is available at the
/// very first start.
///
/// [public] and [neighbour] are the two fields that make a card
/// usable beyond the own segment. They stay empty
/// as long as they are not PROVEN — a guessed public address
/// costs the counterpart a whole ladder step and never finds anyone.
/// Until S384 this function did not even accept them, and every
/// issued card carried only the LAN address.
Card cardFor(
  Identity asValue,
  inv.Invitation e,
  List<CardAddress> own, {
  CardAddress? neighbour,
  List<String> relay = const [],
}) =>
    Card(
      // The relays the node knows (§11.9) — at most three (§15.2).
      relay: relay,
      channel: cardChannel,
      // The current X25519 — NOT for sealing (the card is valid 90 d,
      // the key changes every 7 d). Sealing is done against the bundle.
      letterKeyX25519: asValue.postBox.address.x25519Pk,
      // The identifier — the same across every KEM rotation (S385, E1).
      fingerprint: asValue.postBox.address.identifier,
      ownAddresses: own,
      neighbourAddress: neighbour,
      code: e.code,
      expiryUnixSeconds: e.expiryUnixSeconds,
      difficulty: e.difficulty,
    );

/// Whether an arriving packet counts as a sign of life OF THE COUNTERPART.
///
/// Measured on 14.09.2026: every one counted. A holder, however, acknowledges
/// every deposit with 0x31, and this packet comes from HIM — he is
/// in the found neighbours, so the sign of life meant
/// „step neighbour carries". The ladder thereupon stopped the more expensive
/// post box, resumed it after the silence period, deposited
/// again, got another receipt — 10 deposits in 1200 ms at
/// 120 ms period (`smoke_ladder`), so with the real values roughly 23 KB
/// every two seconds per unacknowledged message, without end.
///
/// **The proof that the deposit works was read as proof
/// that it is unnecessary.** A packet from the post box range says
/// something about the DEPOSIT, never about the recipient.
///
/// A block list and not an allow list, on purpose: an
/// allow list would have to be maintained with every new kind, and whoever
/// forgets it builds exactly this error anew. Whoever adds a kind
/// that likewise says nothing about the counterpart enters it HERE.
///
/// S387: the update (0x70-0x7F) belongs to it. A piece of the
/// public update comes from the HOLDER, who is a neighbour, and says
/// nothing about whether the recipient of an open sending is reachable.
///
/// S391: the board (0x43/0x44) likewise — it comes from a
/// NEIGHBOUR and says nothing about the recipient of a sending.
bool countsAsSignOfLife(int kind) =>
    !kinds.isPostBox(kind) &&
    !kinds.isUpdate(kind) &&
    !kinds.isBoard(kind);

/// Did this packet come from the own segment?
///
/// The question separates step 1 from step 2 (§7.1: „LAN address" versus „public
/// address") and is DECIDABLE from the sender address — an address
/// that is not routed in the open network can only have reached a packet via the
/// own segment.
///
/// True for: the loopback, the private IPv4 ranges per RFC 1918
/// ([isPrivate]), IPv4 link-local 169.254.0.0/16 (RFC 3927), IPv6
/// link-local fe80::/10 (RFC 4291) and IPv6 ULA fc00::/7 (RFC 4193).
///
/// False — and this is the case one easily includes — for
/// 100.64.0.0/10 (RFC 6598, CGNAT). A counterpart behind CGNAT is
/// not in the own segment; its packet came via step 2, and exactly there
/// the remembered route belongs.
///
/// [isPrivate] stays unchanged: it answers a different question
/// („is this address fit as a public address in a card",
/// `host_outside.dart`, `mailbox_invitation.dart`, `node_outside.dart`),
/// and an additional range there would be a change at three
/// unmeasured places.
bool outTheSegment(InternetAddress a) {
  if (a.isLoopback) return true;
  final b = a.rawAddress;
  if (a.type == InternetAddressType.IPv4) {
    if (b.length == 4 && b[0] == 169 && b[1] == 254) return true; // RFC 3927
    return isPrivate(a);
  }
  if (b.length != 16) return false;
  if (b[0] == 0xFE && (b[1] & 0xC0) == 0x80) return true; // fe80::/10
  if ((b[0] & 0xFE) == 0xFC) return true; // fc00::/7
  return false;
}


/// Via which step a packet came in.
///
/// **The step is in the PACKET, not in the neighbour list.** [kind] is the
/// first byte as it came from the wire; §8.1 gives forwarding 0x20/0x21
/// and §8.2 gives the post box 0x30-0x36, and both are thus readable from the
/// packet. Everything else came in directly and is step 1 or 2 — which
/// of the two is told by the sender address ([outTheSegment]).
///
/// Measured on 16.09.2026 (finding B-5, `berichte/S390-EVAL-NACHRICHT.md`):
/// until here this function concluded from „the sender is in my
/// neighbour list" that it was step 3. That is a PROPERTY OF THE SENDER and
/// no statement about the ROUTE: a counterpart in the same segment that
/// is also a neighbour delivered directly and was remembered as step 3
/// (`[A] zugestellt ueber nachbar`, although only `lan` had been started). The
/// remembered route moves into probation per §7.1, and the next
/// message then first goes via a step that has never carried.
///
/// The neighbour list is therefore no longer in the signature: it cannot
/// answer the question, and a parameter that one passes only because
/// it was needed earlier is the invitation to draw the same conclusion
/// once more.
///
/// Guard: `test/smoke_step_out_packet.dart`.
LadderStep stepFrom(int kind, InternetAddress from) {
  if (kinds.isForward(kind)) return LadderStep.neighbour;
  if (kinds.isPostBox(kind)) return LadderStep.postBox;
  return outTheSegment(from) ? LadderStep.lan : LadderStep.public;
}

/// Passes an arriving packet as a sign of life to the [open]
/// sendings — for the step via which it REALLY came ([stepFrom]), and
/// only if it says something about a counterpart
/// ([countsAsSignOfLife]).
///
/// **It is not bound to the recipient of the sending.** Every packet from
/// anywhere counts for EVERY open sending. Measured on 16.09.2026
/// (`berichte/S389-BAU-QUITTUNG.md`, measurement 2): a node D that has nothing
/// to do with the sending sends a message — and the sending to
/// the unreachable C reports "briefkasten stillgestellt — lan traegt",
/// although C never answered.
///
/// From this follows a limit that is easily overlooked when building: a
/// sign of life may PAUSE a sending, but never END it. Whoever
/// takes it as the end loses the deposit precisely for the
/// recipient who needs it — one foreign packet at the wrong
/// time suffices. Where a sending must end without a receipt, the
/// caller decides that from evidence that belongs to THIS recipient
/// ([Target.postBoxApplicable]).
void signOfLifeDistribute(
  Uint8List data,
  InternetAddress from,
  Iterable<Shipment> open,
) {
  if (data.isEmpty || !countsAsSignOfLife(data[0])) return;
  final step = stepFrom(data[0], from);
  for (final s in open) {
    s.signOfLife(step);
  }
}

/// The network interfaces read at start — read only.
///
/// They live here and not as a static on the node: it is a property
/// of the MACHINE, not of a node, and `node.dart` was thereby over
/// the line budget. Two nodes in the same process share them anyway.
List<NetworkInterface> get interfaces => _immediateInterfaces;
List<NetworkInterface> _immediateInterfaces = const [];

/// Must be called once before the first card generation —
/// `NetworkInterface.list` is asynchronous, [cardFor] is not supposed to be.
///
/// **Without restriction to an address type** (S390). Until then here stood
/// `type: InternetAddressType.IPv4`, and thereby a node never saw its own
/// IPv6 — neither for the card ([ownLanAddress]) nor for the
/// comparison „is that myself?" (`node_call.dart`). §11.1 requires
/// both address types on the wire; an address the node does not
/// know it cannot offer either.
///
/// The defaults of `NetworkInterface.list` leave out loopback AND
/// link-local (measured 16.09.2026: without `type` exactly the
/// same three IPv4 addresses came out here as before, the `fe80::` only with
/// `includeLinkLocal: true`). Neither is fit for any card.
///
/// The readers of this list are measurably unaffected: `host_outside.dart:235`
/// and `smoke_outside_source.dart:101` check for IPv4 themselves before they
/// ask [isPrivate]; `node_call.dart:105` only compares for equality
/// and with IPv6 in the list recognises MORE own addresses — without this
/// step a node enters itself as a neighbour as soon as
/// IPv6 neighbours are remembered.
Future<void> interfacesRead() async {
  _immediateInterfaces = await NetworkInterface.list();
}

/// The base construction of a node: wire, shell, cover stream.
///
/// Three lines, and still a function of its own — because the ORDER
/// is the statement. The shell (§4.2 „an additional shell underneath it")
/// lies between wire and splitter; whatever is built afterwards gets it and
/// not the wire. Whoever passes the wire through here bypasses the pairwise
/// wrapping and puts plaintext on the data port again (§5.5 rule 3). In
/// `node.dart` this stood as a comment next to three assignments; here it stands
/// at the place where it applies.
Future<(Wire, Shell, cover.CoverStream)> socketBuild(
    {required int port, required void Function(String) report}) async {
  // The interfaces are already here: `Host.start` reads them before
  // the node starts. Passing them along saves the second system call and
  // — more importantly — lets the wire see the same environment as the card.
  final wire = await Wire.open(
      port: port, interfaces: interfaces, report: report);
  // S391 (W6): the passive proof lies UNDER the shell — only there is the
  // first packet of a stranger visible before the own handshake answer.
  final proof = ReachabilityProof(wire);
  final shell = Shell(proof, report: report);
  final coverStream =
      cover.CoverStream((p, z) => shell.sendCover(p, z.$1, z.$2));
  proofAttach(coverStream, proof);
  return (wire, shell, coverStream);
}

/// Where an arriving packet belongs — the kind allocation.
///
/// Stood until S390 as `_inbound` in `node.dart`. It is not
/// better placed there: `node.dart` owns the socket and wires the
/// parts, and this method makes no decision of its own — it reads
/// the kind byte and passes it on. The occasion for the cut was the
/// line budget (mycelium/README.md rule 2), the place is still the
/// right one: here are the helpers that every part of the node needs.
///
/// The ranges come EXCLUSIVELY from `kinds.dart` (`isFirstContact`
/// and siblings); an own enumeration of numbers would be exactly the
/// second place per number that `check-mycelium-rules.sh` rule 4 prevents.
extension Assignment on Node {
  void assign(Uint8List data, InternetAddress from, int fromPort,
      {bool withoutReturnRoute = false}) {
    if (data.isEmpty) return;
    final origin = CardAddress(Uint8List.fromList(from.rawAddress), fromPort);
    // Fetched from a compartment or forwarded: the address belongs to the holder
    // or to the forwarder and is not fit as a return route.
    final returnRoute = withoutReturnRoute ? null : origin;
    try {
      final s = data[0];
      if (kinds.isFirstContact(s)) {
        // S394: the first contact had no line on arrival — a lost request
        // and one that arrived but was not answered looked the same.
        report('First contact packet 0x${s.toRadixString(16).padLeft(2, '0')} '
            'in (${data.length} B, '
            '${withoutReturnRoute ? "forwarded or collected" : "direct"})');
        firstContact(data, origin, returnRoute);
      } else if (kinds.isMessage(s)) {
        toOneIdentity(data, origin, returnRoute);
      } else if (kinds.isAmendment(s)) {
        amendmentToOneIdentity(data, origin);
      } else if (kinds.isForward(s)) {
        codeRoute.receive(data, from, fromPort);
      } else if (kinds.isPostBox(s)) {
        postBoxDeposit.receive(data, from, fromPort);
      } else if (kinds.isBoard(s)) {
        // Forwarded or collected: `von` is not the asker.
        if (!withoutReturnRoute) board?.receive(data, from, fromPort);
      } else if (kinds.isOutsideRoute(s)) {
        outsideRoute.receive(data, from, fromPort);
      } else if (kinds.isMedia(s)) {
        mediaReception?.receive(data, from, fromPort);
      } else if (kinds.isGroup(s)) {
        groupsReception?.call(data);
      } else if (kinds.isUpdate(s)) {
        updateReception?.call(data, from, fromPort);
      } else {
        report('unknown kind $s discarded');
      }
    } on Object catch (e) {
      report('discarded — $e');
    }
  }
}
