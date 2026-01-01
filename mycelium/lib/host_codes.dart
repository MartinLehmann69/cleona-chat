/// The seam between the host and steps 3 and 4 (V4.2 §8.1, §8.2;
/// proposal M from S391, wired in S392).
///
/// `node_codes.dart` and `node_post_box.dart` are built, but they
/// know nothing about identities. What only a mailbox knows — under
/// which codes packets for it come, which day key a contact
/// has published, to which identifier a contact belongs at all —
/// they fetch via callbacks. Those are set here, and only here: the
/// [Host] is the only place that holds BOTH, the node and all
/// mailboxes (§4.5.1 — one daemon, one port, all identities active).
///
/// Until S392 nobody set them. The default values deliver the empty list
/// and `null`; with that the node denied its own codes
/// (`isOwnCode` always `false`), registered pure noise with its fixed neighbour,
/// and step 4 dropped out with "no contact" — for a contact reachable only
/// via the internet **not a single** packet went
/// out (`berichte/S392-M1-VERDRAHTUNG-FAKTEN.md`).
///
/// A separate file because `host.dart` stands at the 400-line limit
/// (`mycelium/README.md`, `scripts/check-mycelium-rules.sh`). It gets by with the
/// public side of the host: [Host.mailboxes] and [Host.node].
///
/// ── NO CLOCK ────────────────────────────────────────────────────────
///
/// No clock, no packet at idle (working rule 5). [codesChanged]
/// empties the day cache and forgets the registration state; sending happens
/// only if the cover stream is STOPPED (`CodeRoute.edge`) — it always runs
/// (§5.1, `node.dart` starts it), so each of these edges costs
/// zero packets and zero bytes. The registration rides along in the next cover draw
/// (§5.5). The UTC day change likewise needs no clock: every
/// reader computes `_today` fresh.
library;

import 'package:mycelium/node_post_box.dart';
import 'package:mycelium/node_helpers.dart' show hexFrom;
import 'package:mycelium/mailbox.dart';
import 'package:mycelium/mailbox_pair.dart';
import 'package:mycelium/host.dart';

extension HostCodes on Host {
  /// The node-wide callbacks of steps 3 and 4. Called from
  /// `Host._wireUp()`, once — the closures read [mailboxes]
  /// only on call, so a mailbox registered later counts along without
  /// renewed wiring (the same construction as `knoten.gruppenEmpfang`).
  void codesWireUp() {
    // §8.1: the codes of this DEVICE are the union over all
    // registered identities — the neighbour knows no identities.
    node.codeRoute.inboundCodes =
        (day) => [for (final p in mailboxes) ...p.inboundCodes(day)];
    // §8.1/§4.3 (AS-2): `K_AB` depends on BOTH founding keys — on the
    // contact AND on the sending identity. Therefore exactly
    // its mailbox is asked, never "the first one that knows the contact": that delivered
    // a silently wrong code with several identities. The same rule
    // and the same construction as `node.routesTo` (`host.dart`).
    node.codeRoute.pairFrom =
        (contact, from) => mailboxFor(from)?.pairFrom(contact);
    // §8.1 `0x23` (AS-3): the content is the own fixed neighbour address,
    // sealed symmetrically under `K_AB` — 47 B (IPv4) or 59 B (IPv6),
    // 1140 B are allowed. Only the identity that searches may seal,
    // because `K_AB` depends on BOTH founding keys (§4.3); therefore
    // [from], as with `pairFrom` and for the same reason.
    //
    // On 22.09.2026 a producer stood here briefly that built a whole
    // MESSAGE (hybrid envelope, 7752 B). It fell the same day:
    // a `0x23` is ONE part, and the hybrid overhead with a fixed
    // 7736 B is too large for every payload — even for the empty one. §8.1 says
    // "one part, no message inside"; that was not a recommendation but
    // the build rule. Reasoning for the seal: `mailbox_pair.dart`,
    // at `suchContentSeal`.
    node.codeRoute.whereAreYouContent =
        (contact, from) => mailboxFor(from)?.whereAreYouContent(contact);
    // The opposite direction. Unlike when sending, the arriving
    // packet names NO identity — it only carries the code (proposal M). So
    // ask every mailbox until one has a contact that sends under
    // this code AND whose `K_AB` opens the seal. A
    // foreign mailbox cannot deliver anything silently wrong here: it
    // does not find the code, and if it found it, the seal would not
    // open (Poly1305).
    node.codeRoute.whereAreYouAccept = (code, content) {
      for (final p in mailboxes) {
        if (p.whereAreYouAccept(code, content) != null) return true;
      }
      return false;
    };
    // §8.2: the day pubkey depends on the contact of ONE mailbox. A
    // foreign one delivers `null` (it does not know the contact) or the same
    // value (the day key belongs to the counterpart, not to me) — the
    // first hit is therefore right, unlike with `pairFrom`, where the
    // pair secret depends on BOTH founding keys (§4.3).
    node.dayPkFrom = (contact, day) {
      for (final p in mailboxes) {
        final pk = p.dayPkFrom(contact, day);
        if (pk != null) return pk;
      }
      return null;
    };
    // Step 4 names only the identifier (`ladder.dart`, `DepositSend`), never
    // the sending identity — so ask every mailbox until one knows the
    // contact.
    node.contactFrom = (identifier) {
      final hex = hexFrom(identifier);
      for (final p in mailboxes) {
        final k = p.contactOrNull(hex);
        if (k != null) return k.address;
      }
      return null;
    };
    // §8.2 (proposal 6.4): step 4 leaves post first with the recipient's
    // fixed neighbours as it told them — the first mailbox that knows it.
    node.neighboursFrom = (contact) {
      for (final p in mailboxes) {
        final k = p.contactOrNull(identifierFrom(contact));
        if (k != null) return k.neighbours;
      }
      return const [];
    };
  }

  /// What connects a newly admitted mailbox with steps 3 and 4.
  /// Called from `Host._admit`, once per mailbox.
  void codesAdmit(Mailbox p) {
    p.underCodeSend = node.codeRoute.underCodeSend; // §8.1
    // §9.2 (proposal rule 5): the fixed neighbours ride sealed in every
    // message and acknowledgement of this identity, as IT names them (D3),
    // and a contact's arrive the same way.
    p.identity.messages
      ..ownNeighbours = (() => p.ownNeighbours)
      ..onNeighbours = p.neighboursHeard;
    p.dayKeyDistribute(); // §8.2, edge "mailbox registered"
    // EDGE: this mailbox brings codes along (contacts, invitations,
    // open joins). Without it the day cache of
    // `isOwnCode` would stay on the old set for up to one second, and
    // a packet arriving immediately under one of the new codes would be
    // rejected (`node_codes.dart`, throttle `_freshComputed`).
    node.codeRoute.codesChanged();
  }

  /// Edge "mailbox deregistered": its codes no longer apply. Called
  /// from `Host.deregister`, AFTER the removal from the list — otherwise
  /// the recomputation would register exactly the codes again that have just
  /// dropped away.
  void codesDeregistered() => node.codeRoute.codesChanged();
}
