/// The update at the host — the public update on mycelium (S387).
///
/// Three parts, ONE entry point for the seam ([updateAttach]):
///
/// | Part | File | Decision |
/// |---|---|---|
/// | manifest in the post box | `update_manifest_compartment.dart` | M1+ |
/// | fetch pieces | `update_assembler.dart` | P1 |
/// | hand out pieces | `update_holder.dart` | P1 (always-on node) |
///
/// ── WHAT THE SEAM MUST DO ──────────────────────────────────────────────
///
/// 1. After `Host.start`: `service.updateTraeger =
///    aktualisierungAnbinden(wirt, kanal: …)`. Setting it is the moment
///    „start".
/// 2. At the moments network change, app opened, new neighbour:
///    `service.updateManifestFragen()`.
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
import 'package:mycelium/node.dart';
import 'package:mycelium/node_post_box.dart';
import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/update_holder.dart';
import 'package:mycelium/update_manifest_compartment.dart';
import 'package:mycelium/update_assembler.dart';
import 'package:mycelium/update_piece.dart';
import 'package:mycelium/host.dart';

/// The entry point for the seam: binds the update to the node of the
/// [host]. [channel] is `kKanalLive`/`kKanalBeta`.
Update updateAttach(
  Host host, {
  required int channel,
  int? Function(Uint8List json) manifestCheck = UpdateCarrier.manifestSequence,
  void Function(String)? report,
}) =>
    Update(host.node,
        channel: channel, manifestCheck: manifestCheck, report: report);

class Update implements UpdateCarrier {
  final Node node;
  final void Function(String)? report;
  late final ManifestCompartment compartment;
  late final UpdateHolder holder;
  late final UpdateAssembler assembler;

  Update(
    this.node, {
    required int channel,
    required int? Function(Uint8List json) manifestCheck,
    this.report,
  }) {
    void send(Uint8List p, UpdateNeighbour target) => node.rawSend(
        p, CardAddress(Uint8List.fromList(target.$1.rawAddress), target.$2));
    holder = UpdateHolder(send: send, report: report);
    assembler = UpdateAssembler(send: send, report: report);
    compartment = ManifestCompartment(
      compartment: manifestValue(channel),
      check: manifestCheck,
      collect: _compartmentCollect,
      deposit: (content, identifier) => node.deposit(content, identifier),
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
    }
  }

  // The deposit handles ONE collection at a time. Until S388 the compartment was dropped
  // when the identity collection ran („this moment is dropped"), and
  // conversely the identity collection lost its moment — measured in
  // `smoke_update_manifest_compartment` (9a)/(9b). Now both queue up in
  // the same queue (`NodePostBox.compartmentCollect`); none gets lost.
  Future<List<Uint8List>?> _compartmentCollect(Uint8List f) =>
      node.compartmentCollect(f);

  // ── UpdateTraeger ────────────────────────────────────────────────────

  @override
  Future<void> manifestAsk() => compartment.ask();

  @override
  void manifestKnown(Uint8List json) => compartment.known(json);

  @override
  set onManifest(void Function(Uint8List json)? callback) =>
      compartment.onManifest = callback;

  @override
  Future<Uint8List?> piecesFetch(
          {required Uint8List contentHash, required int length}) =>
      assembler.fetch(
          object: contentHash, length: length, withWhom: node.depositNeighbours);

  @override
  void fetchAbort() => assembler.abort();

  @override
  void objectHold(
          Uint8List contentHash, Future<Uint8List?> Function() read) =>
      holder.hold(contentHash, read);

  @override
  void objectRelease(Uint8List contentHash) => holder.release(contentHash);
}
