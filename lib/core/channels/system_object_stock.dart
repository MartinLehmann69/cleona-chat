/// The app side of the seam `DurableStock` (build plan S407, v4_2 §16.0):
/// what the transport asks of the system-channel holdings. S407 SK-2.
///
/// SK-4 connects it: `SystemObjectStock(store, isContact: …)` handed to the
/// host of mycelium. Nothing here sends or waits — every method answers
/// from [SystemObjectStore] at once.
library;

import 'dart:typed_data';

import 'package:cleona/core/channels/system_object_store.dart';
import 'package:mycelium/durable_stock.dart';

class SystemObjectStock implements DurableStock {
  final SystemObjectStore store;

  /// Whether a node (`address:port`, the seam's node form) is a device of
  /// one of this user's contacts — holder choice: non-contacts first
  /// (§16.7). The application owns the contacts; SK-4 passes the lookup.
  final bool Function(String nodeId) isContact;

  /// A read channel's identifiers learned at an edge, not fetched (§16.7,
  /// phone) — the application marks them as new.
  final void Function(int channel, List<DurableId> ids)? onLearned;

  /// An object was offered (fetched or deposited) and kept — the views
  /// reload.
  final void Function(int channel)? onKept;

  /// Where the capable nodes are kept across a restart (device data).
  final List<String> Function()? readCapable;
  final void Function(List<String> nodes)? writeCapable;

  SystemObjectStock(this.store,
      {required this.isContact,
      this.onLearned,
      this.onKept,
      this.readCapable,
      this.writeCapable});

  /// Every device holds and names both channels, a phone within 5 MB each
  /// (§16.0, §16.7, D-126 — S426 V1).
  @override
  List<int> heldChannels() => List.of(SystemObjectStore.channels);

  @override
  List<DurableId> held(int channel, {int? sinceHours}) =>
      store.identifiers(channel, sinceHours: sinceHours);

  @override
  Uint8List stateRoot(int channel) => store.stateRoot(channel);

  @override
  bool isHeldOrRejected(DurableId id) =>
      store.isHeld(id.channel, id.hash) || store.isRejected(id.channel, id.hash);

  /// Handed out (0x93) by every device that holds it (D-126).
  @override
  Uint8List? object(DurableId id) =>
      store.objectOf(id.channel, id.hash)?.bytes;

  @override
  DurableVerdict offer(int channel, Uint8List object,
      {required String fromNode}) {
    if (!store.offer(channel, object).kept) return DurableVerdict.rejected;
    onKept?.call(channel);
    return DurableVerdict.kept;
  }

  @override
  Uint8List? headFor(int channel, Uint8List fingerprint) =>
      store.headFor(channel, fingerprint);

  @override
  bool isContactNode(String nodeId) => isContact(nodeId);

  /// Every device holds what it reads (D-126); no channel is only read.
  @override
  List<int> readChannels() => const [];

  @override
  void learned(int channel, List<DurableId> ids) =>
      onLearned?.call(channel, ids);

  @override
  List<String> rememberedCapable() => readCapable?.call() ?? const [];

  @override
  void rememberCapable(List<String> nodes) => writeCapable?.call(nodes);
}
