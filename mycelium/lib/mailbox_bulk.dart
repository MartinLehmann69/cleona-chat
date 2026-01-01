/// The bulk lane for one identity (§9.4 lane 3): place an object for a
/// contact, collect an announced one. The seam P2b calls.
///
/// A separate file for the same reason as `mailbox_group.dart`: the line
/// budget of `mailbox.dart`. It gets by with the public side of [Mailbox]
/// and [Host.bulk].
///
/// What is NOT here: SENDING the announcement. It carries `K_T`, length,
/// SHA-256 and the holder list ([bulkAnnouncement], `bulk_announce.dart`),
/// and it is an ordinary sealed message (§4.3, §9.4) — the layer above
/// sends it like text, to every recipient over its own leg (§16.2). Its
/// acknowledgement waits until the object decodes (§9.4, Q1).
library;

import 'dart:typed_data';

import 'package:mycelium/bulk_announce.dart';
import 'package:mycelium/bulk_collect.dart';
import 'package:mycelium/bulk_place.dart';
import 'package:mycelium/card.dart' show CardAddress;
import 'package:mycelium/mailbox.dart';

extension MailboxBulk on Mailbox {
  /// Holder candidates for a transfer to [contactIdentifier], in the order
  /// of D-30: the contact's fixed neighbours as it last told them (§9.2),
  /// then the own fixed neighbours, then other reachable neighbours.
  /// Throws [MailboxError] for an unknown contact.
  List<CardAddress> bulkHolders(String contactIdentifier) {
    final k = contact(contactIdentifier);
    final told = node.codeRoute.pairFrom(k.address, address)?.neighbours;
    return host.bulk.holderOrder(told ?? const []);
  }

  /// Holder candidates for ONE transfer to several contacts — a group
  /// places once (§9.4 "encode once, place once", §17.6): the fixed
  /// neighbours every recipient last told, taken in turn so that no member
  /// is served only from the tail, then the own ones. A recipient the
  /// mailbox does not know contributes nothing to the front (it told
  /// nothing) and is no error here.
  List<CardAddress> bulkHoldersFor(Iterable<String> contactIdentifiers) {
    final lists = <List<CardAddress>>[];
    for (final id in contactIdentifiers) {
      final k = contactOrNull(id);
      if (k == null) continue;
      lists.add(node.codeRoute.pairFrom(k.address, address)?.neighbours ??
          const []);
    }
    final told = <CardAddress>[];
    for (var i = 0; lists.any((l) => i < l.length); i++) {
      for (final l in lists) {
        if (i < l.length) told.add(l[i]);
      }
    }
    return host.bulk.holderOrder(told);
  }

  /// Places [object] for [contactIdentifier] with the holders of
  /// [bulkHolders]. One transfer at a time per node; see [BulkPlacer].
  /// [transferKey]: the `K_T` of an announcement already sent (lane 2
  /// falling back, §17.6); otherwise a fresh one.
  Future<BulkPlaced> bulkPlace(String contactIdentifier, Uint8List object,
          {void Function(int sent, int total)? progress,
          Uint8List? transferKey}) =>
      host.bulk.placer.place(object, bulkHolders(contactIdentifier),
          progress: progress, transferKey: transferKey);

  /// Places [object] ONCE for all [contactIdentifiers] ([bulkHoldersFor]).
  /// [resume]/[onAssigned]: an interrupted run continued after a restart
  /// (S398-W1, see [BulkResume]).
  Future<BulkPlaced> bulkPlaceFor(
          Iterable<String> contactIdentifiers, Uint8List object,
          {void Function(int sent, int total)? progress,
          Uint8List? transferKey,
          BulkResume? resume,
          void Function(List<CardAddress?> assigned)? onAssigned}) =>
      host.bulk.placer.place(object, bulkHoldersFor(contactIdentifiers),
          progress: progress,
          transferKey: transferKey,
          resume: resume,
          onAssigned: onAssigned);

  /// The collector of THIS identity (S401): its transfers, its opened
  /// blocks in its own folder under its own key (`HostMedia.admit`). Throws
  /// [StateError] once the mailbox is deregistered.
  BulkCollector get bulkCollector => host.bulk.collectorOf(ownIdentifier);

  /// Keeps pieces of a fallen-back stream for the collection to come
  /// (`BulkCollector.stash`, survives a restart).
  void bulkStash(Uint8List tag, Map<int, Map<int, Uint8List>> pieces) =>
      bulkCollector.stash(tag, pieces);

  /// The announcement of a placed object (`bulk_announce.dart`): `K_T`,
  /// length, SHA-256, the holders that accepted, and [preview].
  Uint8List bulkAnnouncement(BulkPlaced placed, {Uint8List? preview}) =>
      bulkAnnouncePack(
          transferKey: placed.transferKey,
          length: placed.length,
          sha256: placed.sha256,
          holders: placed.holderAddresses,
          preview: preview);

  /// Collects an announced object; see [BulkCollector.collect]. [seed]:
  /// pieces a lane 2 attempt already opened (`StreamFallback.pieces`).
  ///
  /// THE CALLER KEEPS WHAT IS OPEN (S401): the delivery layer remembers no
  /// collection across a restart. The layer above holds it in the store of
  /// this identity and calls this again after the attach, with [started] —
  /// when the announcement came; the complete stripes then come back from
  /// this identity's folder and only the rest is asked.
  Uint8List bulkCollect({
    required Uint8List transferKey,
    required int length,
    required Uint8List sha256,
    required List<CardAddress> holders,
    OnBulkObject? onObject,
    OnBulkFailure? onFailure,
    OnBulkProgress? progress,
    Map<int, Map<int, Uint8List>>? seed,
    DateTime? started,
  }) =>
      bulkCollector.collect(
          transferKey: transferKey,
          length: length,
          sha256: sha256,
          holders: holders,
          onObject: onObject,
          onFailure: onFailure,
          progress: progress,
          seed: seed,
          started: started);
}
