/// The cover route of the public update (§5.5 rule 2, §26.6.1 „Push over
/// cover fill") — the ONLY place where the cover stream and the update
/// know each other. S392.
///
/// ── WHY THIS FILE EXISTS AT ALL ───────────────────────────────
///
/// The five files of the fetch path (`update_piece`, `update_holder`,
/// `update_assembler`, `update_manifest_compartment`, `update`) must not even name the
/// cover stream — `smoke_update_piece` probe (10) records
/// that, and the reason is §3.1: the fetch path carries the update even with the
/// cover stream switched off, and that stays checkable only as long as it does
/// not know it. Conversely `cover_stream.dart` must know nothing of the update
/// (its header: „otherwise holds NOTHING of the send path of real packets").
///
/// Both sides therefore carry only an empty plug-in point —
/// [CoverStream.nextPiece] and [CoverStream.onPiece] —, and this
/// file plugs them together. It is thus also the place where one
/// pulls the whole route out again: whoever does not call [updateCoverRouteAttach]
/// has the state from before S392, and the update still arrives.
///
/// ── WHAT LIES ON THE WIRE ──────────────────────────────────────────────
///
/// The **raw fountain block**, 1041 B, the same as in the fetch path
/// (`lib/core/fountain/`) — §26.6.1: „The same blocks also travel as cover
/// fill." No second format, no second object identifier, no second
/// sealing: the pairwise shell of the cover packet is the whole protection,
/// the piece itself is public (§5.5 rule 3).
///
/// **Without the kind 0x72** of the fetch path: the content byte of the cover packet
/// (`kInhaltStueck`) already says what is inside, and a second number space
/// inside would be one more place where two routes can drift
/// apart. 1041 B lie below `kStueckHoechstens` (1156 B).
///
/// ── WHAT IT MUST NOT DO ────────────────────────────────────────────────────
///
/// No timer, no packet, no back channel. Sending happens only in the
/// draw that the clock of the cover stream has drawn anyway; a piece replaces
/// the filling there (§5.5 rule 1). Only what arrived anyway is
/// received; it triggers no answer (§5.5 rule 4).
library;

import 'package:cleona/core/fountain/fountain_block.dart';
import 'package:mycelium/cover_stream.dart';
import 'package:mycelium/update_holder.dart';
import 'package:mycelium/update_assembler.dart';

/// Default for [updateCoverRouteAttach]: push.
bool alwaysPush() => true;

/// Plugs [holder] (give) and [assembler] (take) into [stream].
///
/// [pushes] is the level gate from §5.5: „Retention-bounded nodes keep
/// only their own platform's pieces and **put none into their cover
/// packets**." Which level a device is only the app knows — this
/// layer reads no platform. The seam sets `() => !mobil` here,
/// the same limit that the superseded layer kept as
/// `UpdateCoverFill.pushes`.
///
/// **Only the giving is levelled.** Taking happens on every level, because the
/// assembler accepts only pieces of an object that the node
/// itself has already fetched anyway — i.e. „only their own platform's pieces"
/// (see [UpdateAssembler.aside]).
void updateCoverRouteAttach(
  CoverStream stream,
  UpdateHolder holder,
  UpdateAssembler assembler, {
  bool Function() pushes = alwaysPush,
}) {
  stream
    ..nextPiece = () {
      if (!pushes()) return null;
      return holder.blockNow()?.toBytes();
    }
    ..onPiece = (piece, _, __) {
      // What comes from the wire is nothing the node may fail on:
      // `fromBytes` returns `null` on wrong length or version
      // and never throws.
      final block = FountainBlock.fromBytes(piece);
      if (block != null) assembler.aside(block);
    };
}
