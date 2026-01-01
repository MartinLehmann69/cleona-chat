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

  /// A retention-bounded node (phone) holds none and names none (§16.0).
  @override
  List<int> heldChannels() =>
      store.holds ? List.of(SystemObjectStore.channels) : const [];

  @override
  List<DurableId> held(int channel, {int? sinceHours}) => store.holds
      ? store.identifiers(channel, sinceHours: sinceHours)
      : const [];

  @override
  Uint8List stateRoot(int channel) => store.stateRoot(channel);

  @override
  bool isHeldOrRejected(DurableId id) =>
      store.isHeld(id.channel, id.hash) || store.isRejected(id.channel, id.hash);

  /// Handed out only by a holder (0x93); a phone names nothing, so nobody
  /// has a reason to ask it.
  @override
  Uint8List? object(DurableId id) =>
      store.holds ? store.objectOf(id.channel, id.hash)?.bytes : null;

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

  /// A phone reads both channels without holding them; a holder reads what
  /// it holds.
  @override
  List<int> readChannels() =>
      store.holds ? const [] : List.of(SystemObjectStore.channels);

  @override
  void learned(int channel, List<DurableId> ids) =>
      onLearned?.call(channel, ids);

  @override
  List<String> rememberedCapable() => readCapable?.call() ?? const [];

  @override
  void rememberCapable(List<String> nodes) => writeCapable?.call(nodes);
}
