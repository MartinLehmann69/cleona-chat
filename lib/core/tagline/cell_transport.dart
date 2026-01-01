// The bridge between delivery layer and link layer.
//
// Until here the delivery layer BUILT cells, but sent none.
// This file is the seam — and it is deliberately thin: it
// computes nothing, it decides nothing, it only assigns.
//
// OUT. `LinkChannel.send(inner)` wants exactly `kCellPlaintextSize` bytes
// and seals itself. The slot delivers a frame body; from it
// a frame is made (`buildInner`), and that goes out. Both functions
// come from the FROZEN AP-3a module — no parser of its own is built here
// and no format re-invented.
//
// IN. From `channel.inbound` come opened frame streams. What
// is inside must be assigned — and that is the one place
// where a decision is necessary:
//
//   Am I r1 (strip and pass on), r2 (redeem path block), or
//   is the cell for me?
//
// The type is NOT in plaintext, and that is intentional: §5.1 invariant 3
// demands sealed content, a role byte would be a difference that
// an observer sees. The assignment therefore happens by ATTEMPT —
// two AEAD attempts, in fixed order. Both fail silently
// if they do not fit (E-83).
//
// WHAT THIS FILE DOES NOT DO: resolve the third possibility ("the cell is for
// me"). That needs the comparison against the own
// tag set, and that is known to the application level, not the transport. It
// returns `mine`, together with the body — whoever can assign it does so.
library;

import 'dart:typed_data';

import 'package:cleona/core/bulk/bulk_frames.dart'
    show BulkFrame, parseBulkFrame;
import 'package:cleona/core/link/connect.dart' show LinkChannel;
import 'package:cleona/core/link/frame.dart'
    show LinkFrame, LinkFrameType, buildInner, parseInner;

import 'reassembly.dart';
import 'relay.dart';
import 'secure_frames.dart';

/// Which role this node has for an incoming cell.
enum CellRole {
  /// First hop: strip and pass on to [InboundCell.nextHop].
  forward,

  /// Second hop: path block redeemed, deliver to [InboundCell.nextHop].
  deliver,

  /// Neither — possibly for this node itself. The comparison
  /// against the own tag set happens one level higher.
  mine,

  /// None of it could be assigned.
  unknown,

  /// A control frame: placement or harvest (Secure mode).
  control,

  /// A frame of the bulk lane (§9.3, frame type `0x05`): placement of a
  /// fountain block, sampling of a line, or an answer to it.
  ///
  /// ── WHY THIS IS A ROLE OF ITS OWN AND NOT [control] ──────────────
  ///
  /// Because both have different OUTFLOWS and that must not
  /// be blurred. A control frame takes a slot of the cover stream (one
  /// cell per `kSlotInterval`); a bulk frame runs via the second
  /// outflow at `R_bulk` (§9.3: "the §5.1 invariants … do **not** govern
  /// bulk cells"). If they ran under the same role, every
  /// consuming site would have to look up the difference in the content — and the
  /// first one that forgets pushes 6348 blocks into a queue of
  /// 120 (98.1 % silent loss, measured).
  ///
  /// Until 02.09.2026 these frames silently fell to the floor here:
  /// `if (f.type != spore) continue`. `bulk_block_seal.dart` built the
  /// type, `frame.dart` carried it, and nobody accepted it.
  bulk,
}

final class InboundCell {
  final CellRole role;

  /// Where to next (for [CellRole.forward]) or to whom (for
  /// [CellRole.deliver]).
  final Uint8List? nextHop;

  /// The body: the cell to be passed on, the message, or the
  /// unassigned frame body.
  final Uint8List body;

  /// Why it did not continue, if it did not continue.
  final RelayReject? reject;

  /// For [CellRole.control]: the read control frame.
  final SecureFrame? control;

  /// For [CellRole.bulk]: the read bulk frame (§9.3).
  final BulkFrame? bulk;

  InboundCell(this.role, this.body,
      {this.nextHop, this.reject, this.control, this.bulk});
}

final class CellTransport {
  final LinkChannel channel;

  /// The link key of THIS connection, from the handshake.
  ///
  /// It is passed in and not pulled from the channel: keys
  /// belong to the link layer, and a getter for them would be a door that
  /// nobody needs.
  final Uint8List linkKey;

  final ReplayGuard guard;

  /// Finds the link key for a path block — the open wire question
  /// from `relay.dart`, here likewise only passed in.
  final LinkKeyLookup blockLookup;

  CellTransport({
    required this.channel,
    required this.linkKey,
    required this.blockLookup,
    ReplayGuard? guard,
  }) : guard = guard ?? ReplayGuard();

  /// Reassembles fragmented frames. Per session, because the
  /// transfer identifiers apply per connection — and because a partner
  /// can thus bind only its own memory, not everyone's.
  final FrameReassembler reassembler = FrameReassembler();

  /// Sends a frame body out.
  void emit(Uint8List frameBody) {
    final inner = buildInner([LinkFrame(LinkFrameType.spore, frameBody)]);
    channel.send(inner);
  }

  /// Sends a control frame out IMMEDIATELY, without a slot.
  ///
  /// **Only for ANSWERS.** An answer is forwarding traffic and
  /// as such not covered by the cover anyway (appendix B-17) — its
  /// timing depends on the request, not on the node. What a node sends
  /// ON ITS OWN, on the other hand, must take a slot, otherwise it is a
  /// spike in the stream and invariant 1 falls. Whoever pushes a
  /// self-initiated message through here undermines the whole
  /// cover idea.
  void emitControl(Uint8List body) => emitFrame(LinkFrameType.control, body);

  /// Like [emitControl], but with a freely chosen frame type — for fragments
  /// that carry their type themselves.
  void emitFrame(int type, Uint8List body) {
    channel.send(buildInner([LinkFrame(type, body)]));
  }

  /// Wraps a frame body and returns the finished inner,
  /// without sending it — for passing on and for tests.
  Uint8List wrap(Uint8List frameBody) =>
      buildInner([LinkFrame(LinkFrameType.spore, frameBody)]);

  /// Redeems a path block that did NOT come via this connection.
  ///
  /// WHAT FOR. A node can be both hops for the same cell: the
  /// sender's slot plan chooses r1 (invariant 4, §5.1), the
  /// recipient chooses r2 in its liveness (§6) — the two choices
  /// know nothing of each other, and in a small network the same
  /// node is often the only partner of both sides. Then `r1 == r2`.
  ///
  /// [classify] does not see that: it tries in order "am I r1"
  /// and "am I r2", and the FIRST probe hits — the cell counts as
  /// to be passed on. But the stripped body is exactly the cell that
  /// this node could redeem as r2. Without this path it ends in
  /// `kein Weg zum naechsten Hop` and the message is gone.
  ///
  /// The replay guard is the same as on the normal path — a cell
  /// redeemed here is afterwards used up there as well.
  ({DeliverDecision? ok, RelayReject? reject}) redeemLocally(
          Uint8List forwarded, int epoch) =>
      deliverSecondHop(
          forwarded: forwarded,
          epoch: epoch,
          lookup: blockLookup,
          guard: guard);

  /// Assigns an incoming frame stream.
  List<InboundCell> classify(Uint8List inner, int epoch) {
    final out = <InboundCell>[];
    final List<LinkFrame> frames;
    try {
      frames = parseInner(inner);
    } catch (_) {
      // A malformed frame stream is no reason to crash. It
      // carries no information and is silently discarded — the same
      // stance as for a cell that does not authenticate (§2.6).
      return out;
    }
    for (final raw in frames) {
      // Fragments come together here BEFORE anything interprets them. A
      // reassembled frame then goes through exactly the same
      // dispatcher as an unfragmented one — there is no second path.
      // Reassembly happens only at the endpoint: a relay passes cells
      // on and does not see the connection between them.
      final f = reassembler.offer(raw.type, raw.body);
      if (f == null) continue;
      // Control channel: placement and harvest (Secure). Comes before the
      // role probe because it can be recognised unambiguously by the frame type
      // and needs no trial decryption.
      if (f.type == LinkFrameType.control) {
        final c = parseSecureFrame(f.body);
        if (c != null) {
          out.add(InboundCell(CellRole.control, f.body, control: c));
        }
        continue;
      }
      // Bulk lane (§9.3). Like the control channel recognisable by the frame type,
      // so before the role probe — and with a role of its OWN, so that it does not
      // get into the slot outflow (see [CellRole.bulk]).
      if (f.type == LinkFrameType.fountain) {
        final b = parseBulkFrame(f.body);
        if (b != null) {
          out.add(InboundCell(CellRole.bulk, f.body, bulk: b));
        }
        continue;
      }
      if (f.type != LinkFrameType.spore) continue;

      // 1. Bin ich r1?
      final fwd =
          forwardFirstHop(cell: f.body, linkKeyOfIncoming: linkKey);
      if (fwd != null) {
        out.add(InboundCell(CellRole.forward, fwd.cell, nextHop: fwd.nextHop));
        continue;
      }

      // 2. Bin ich r2?
      final del = deliverSecondHop(
          forwarded: f.body,
          epoch: epoch,
          lookup: blockLookup,
          guard: guard);
      if (del.ok != null) {
        out.add(InboundCell(CellRole.deliver, del.ok!.message,
            nextHop: del.ok!.handle));
        continue;
      }

      // 3. Neither. A replay is reported as such — it is not a
      //    "maybe for me", but a rejected attempt.
      out.add(InboundCell(
          del.reject == RelayReject.replay ? CellRole.unknown : CellRole.mine,
          f.body,
          reject: del.reject));
    }
    return out;
  }
}
