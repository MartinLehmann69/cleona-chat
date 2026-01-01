/// The update at the host — the public update on mycelium (S387).
///
/// Three parts, ONE entry point for the seam ([updateAttach]):
///
/// | Part | File | Decision |
/// |---|---|---|
/// | manifest in the post box | `update_manifest_compartment.dart` | M1+ |
/// | fetch pieces | `update_assembler.dart` | P1 |
/// | the target's partial state on disk | `update_partial.dart` | S406 P2 |
/// | hand out pieces | `update_holder.dart` | P1 (always-on node) |
///
/// ── WHAT THE SEAM MUST DO ──────────────────────────────────────────────
///
/// 1. After `Host.start`: `service.updateCarrier = updateAttach(host,
///    channel: …, partialDir: …)`. Setting it is the moment „start".
/// 2. At the moments network change, app opened, new neighbour: ask the
///    manifest AND present the known target again (`UpdateOffer.againTry`).
/// 3. Nothing: the constructor attaches [Update.receive] to the
///    distributor of the node (`Knoten.aktualisierungEmpfang`, S387
///    merge). Until then the node discarded 0x70-0x7F as
///    „unknown kind", and only the manifest (post box kinds) carried.
///
/// The update does NOT depend on the cover stream (§3.1, decision A): both routes
/// here run with the cover stream switched off.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/update/update_carrier.dart';
import 'package:mycelium/card.dart' show CardAddress;
import 'package:mycelium/neighbourhood.dart' show Neighbourhood;
import 'package:mycelium/node.dart';
import 'package:mycelium/node_post_box.dart';
import 'package:mycelium/node_collect_queue.dart' show NodeCollectQueue;
import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/post_box_proof.dart' show compartmentQuestion;
import 'package:mycelium/update_holder.dart';
import 'package:mycelium/update_manifest_compartment.dart';
import 'package:mycelium/update_assembler.dart';
import 'package:mycelium/update_piece.dart';
import 'package:mycelium/update_trace.dart';
import 'package:mycelium/host.dart';

/// The entry point for the seam: binds the update to the node of the
/// [host]. [channel] is `kKanalLive`/`kKanalBeta`.
/// [partialDir] is where the partial state of the update target lies (in
/// the profile, S406-UPDPKG P2).
Update updateAttach(
  Host host, {
  required int channel,
  required String partialDir,
  int? Function(Uint8List json) manifestCheck = UpdateCarrier.manifestSequence,
  void Function(String)? report,
}) =>
    Update(host.node,
        channel: channel,
        partialDir: partialDir,
        manifestCheck: manifestCheck,
        report: report);

class Update implements UpdateCarrier {
  final Node node;
  final void Function(String)? report;
  late final ManifestCompartment compartment;
  late final UpdateHolder holder;
  late final UpdateAssembler assembler;

  /// The fetch of a foreign platform's binary (§26.6.3) — a second
  /// assembler with its own directory, so the update target's state is
  /// never deleted for it and vice versa. Pieces name their object, so the
  /// two never take each other's.
  late final UpdateAssembler foreign;

  Update(
    this.node, {
    required int channel,
    required String partialDir,
    required int? Function(Uint8List json) manifestCheck,
    this.report,
  }) {
    void send(Uint8List p, UpdateNeighbour target) => node.rawSend(
        p, CardAddress(Uint8List.fromList(target.$1.rawAddress), target.$2));
    holder = UpdateHolder(send: send, report: report);
    assembler =
        UpdateAssembler(send: send, partialDir: partialDir, report: report);
    foreign = UpdateAssembler(
        send: send, partialDir: '$partialDir-foreign', report: report);
    compartment = ManifestCompartment(
      compartment: manifestValue(channel),
      check: manifestCheck,
      collect: _compartmentCollect,
      deposit: (content, identifier) => node.deposit(content, identifier),
      // §26.5.4: what this node knows, every neighbour asking it is handed.
      holdOwn: (json) => node.postBoxDeposit.holdOwn(manifestValue(channel), json),
      report: report,
    );
    // In the constructor, not in [updateAttach]: whoever builds the
    // class directly (probes, smokes) also gets the packets.
    node.updateReception = receive;
  }

  /// The kind allocation for 0x70-0x7F (see header, point 3).
  void receive(Uint8List packet, InternetAddress from, int fromPort) {
    if (packet.isEmpty || !kinds.isUpdate(packet[0])) return;
    if (packet[0] == kinds.kPiecePlea) {
      holder.receive(packet, from, fromPort);
    } else {
      assembler.receive(packet, from, fromPort);
      foreign.receive(packet, from, fromPort);
    }
  }

  // The compartment and the identity collection ask side by side
  // (`NodeCompartment.compartmentCollect`): at a holder both ask, the
  // questions follow one another, and neither loses its moment
  // (`smoke_update_manifest_compartment` (9a)/(9b)).
  Future<List<Uint8List>?> _compartmentCollect(
      Uint8List f, void Function(Uint8List piece) onPiece) {
    final asked = node.lastHeard;
    updateTrace('ask-holders',
        reason: asked.isEmpty
            ? 'no neighbour heard — not asked'
            : '${asked.length} neighbour(s): '
                '${asked.map((n) => '${n.$1.address}:${n.$2}').join(', ')}');
    return node.compartmentCollect([compartmentQuestion(f)], withWhom: asked,
        onPiece: (p) {
      onPiece(p);
      return true; // the compartment is read, never deleted (§26.5.4)
    });
  }

  // ── UpdateCarrier ─────────────────────────────────────────────────────

  @override
  Future<void> manifestAsk() => compartment.ask();

  @override
  void manifestKnown(Uint8List json) => compartment.known(json);

  @override
  set onManifest(void Function(Uint8List json)? callback) =>
      compartment.onManifest = callback;

  @override
  void objectExpect(Uint8List contentHash, int length) =>
      assembler.expect(contentHash, length);

  /// Whom the fetch path asks, in order (§26.6.1 "after three answers
  /// without a new piece the node turns to the next holder, and after the
  /// last holder it waits for the next moment"): EVERY neighbour, one entry
  /// per node, in the holder rank of a deposit (live link, answered,
  /// confirmed, hint). Not the three holders of a deposit (§8.2): the norm
  /// fixes no count here (OPEN L-3), and with three a collector whose three
  /// best neighbours do not hold the object never asked one that does — at
  /// every moment again the same three (S407-UPDATETARGET).
  List<UpdateNeighbour> get fetchHolders =>
      node.ownHolders(n: Neighbourhood.atMost);

  @override
  Future<String?> objectFetch(
          {required Uint8List contentHash, required int length}) =>
      assembler.fetch(
          object: contentHash, length: length, withWhom: fetchHolders);

  @override
  set onObjectComplete(void Function(Uint8List contentHash, String path)? f) =>
      assembler.onComplete = f;

  @override
  void objectTaken(Uint8List contentHash) => assembler.taken(contentHash);

  @override
  void objectDiscard(Uint8List contentHash) => assembler.discard(contentHash);

  @override
  void fetchAbort() => assembler.abort();

  @override
  Future<String?> foreignFetch(
          {required Uint8List contentHash, required int length}) =>
      foreign.fetch(
          object: contentHash, length: length, withWhom: fetchHolders);

  @override
  void foreignTaken(Uint8List contentHash) => foreign.taken(contentHash);

  @override
  double? foreignProgress(Uint8List contentHash) {
    final p = foreign.partial;
    if (p == null || !sameBytes(p.object, contentHash)) return null;
    return p.progress;
  }

  @override
  void objectHold(
          Uint8List contentHash, Future<Uint8List?> Function() read) =>
      holder.hold(contentHash, read);

  @override
  void objectHoldFile(Uint8List contentHash, String path) =>
      holder.holdFile(contentHash, path);

  @override
  void objectRelease(Uint8List contentHash) => holder.release(contentHash);
}
