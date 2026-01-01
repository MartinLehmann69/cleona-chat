/// The seam between the transport of durable objects (mycelium, SK-1) and
/// the application that owns them (`lib/core/channels/`, SK-2) — as fixed
/// before the build in `mycelium/berichte/S407-SYSTEMKANAELE-BAUPLAN.md`.
///
/// The transport knows no reports, only OBJECTS (bytes) with an identifier.
/// The application decides what is valid (signature, limits per pseudonym,
/// retraction) and what it keeps; the transport decides who is asked and
/// when — never on a clock (§16.0, D-54).
///
/// Node identifiers in this seam ([DurableStock.isContactNode], the
/// `fromNode` of [DurableStock.offer]) are the address of the device as
/// `address:port` — the form `InternetAddress.address` and the data port
/// give. The application maps them to its contacts' known addresses.
library;

import 'dart:typed_data';

import 'package:mycelium/durable_id.dart';

export 'package:mycelium/durable_id.dart' show DurableId;

/// What the application says to an offered object.
enum DurableVerdict {
  /// Valid and within the limits: held from now on (a holder names it).
  kept,

  /// Fetched and refused — signature wrong, limit exceeded, retracted. The
  /// identifier is in the rejected set from now on (§16.0).
  rejected,
}

/// mycelium: what the transport needs from the application.
abstract class DurableStock {
  /// Channels this node holds (desktop: both system channels; phone: none).
  List<int> heldChannels();

  /// Identifiers held for [channel], newest first (for 0x05 and 0x96).
  /// [sinceHours]: only those whose age is at most so many hours.
  List<DurableId> held(int channel, {int? sinceHours});

  /// Hash over sorted held + rejected identifiers of [channel] (§16.0).
  Uint8List stateRoot(int channel);

  bool isHeldOrRejected(DurableId id);

  /// The object for handing out (0x93), or `null`.
  Uint8List? object(DurableId id);

  /// A fetched or deposited object; the app checks signature and limits and
  /// answers kept / rejected (rejected goes into the rejected set).
  DurableVerdict offer(int channel, Uint8List object, {required String fromNode});

  /// Head of the group for a crash fingerprint, or null (0x97 → 0x98).
  Uint8List? headFor(int channel, Uint8List fingerprint);

  /// Holder choice: non-contacts first (§16.7).
  bool isContactNode(String nodeId);

  /// Channels this node reads without holding them (a phone: both system
  /// channels; a desktop: none). At an edge of §16.0 the node asks for their
  /// identifiers and hands them to [learned] instead of fetching (§16.7:
  /// "what it learns at the edges of §16.0 it marks as new without fetching
  /// it"); it fetches only when the user opens the channel.
  List<int> readChannels();

  /// Identifiers of a read channel learned at an edge, neither held nor
  /// rejected, NOT fetched — the application marks them as new.
  void learned(int channel, List<DurableId> ids);

  /// Nodes (`address:port`) that showed the capability before, kept by the
  /// application in the device data across a restart, the most recent
  /// last — so the start edge has someone to ask (§16.0: "a neighbour that
  /// has named an identifier or answered such a question before").
  List<String> rememberedCapable();

  /// The capable nodes changed membership; the application keeps them.
  void rememberCapable(List<String> nodes);
}

/// One step of a deposit (§16.7 "How a report leaves the device").
class DepositEvent {
  /// Holders that acknowledged so far (`0x91`).
  final int acknowledged;

  /// The holder this event is about (`address:port`), if any.
  final String? holder;

  /// Whether that holder is a device of a contact — the preview says so
  /// in one line when a contact holds (§16.7).
  final bool contactHolder;

  /// Two acknowledged: "published". The stream ends after this event.
  bool get published => acknowledged >= 2;

  /// The deposit ended without two acknowledgements: no holder left that
  /// has not failed (or none known). The stream ends after this event; the
  /// report rests and is deposited again at the next edge (§16.7, D-47).
  final bool ended;

  /// Why it ended, for the state "failed" — `null` while it runs.
  final String? reason;

  const DepositEvent(this.acknowledged,
      {this.holder, this.contactHolder = false, this.ended = false, this.reason});

  @override
  String toString() => 'DepositEvent($acknowledged${holder == null ? '' : ' $holder'}'
      '${contactHolder ? ' contact' : ''}${ended ? ' ended: $reason' : ''})';
}

/// The answer to "crash fingerprint known?" (0x97 → 0x98).
class FingerprintAnswer {
  /// The head of the group, or `null`: "unknown".
  final Uint8List? head;

  /// Nobody answered or no holder is known — the device then asks its own
  /// read cache only and lets the user decide (§16.7).
  final bool unanswered;

  const FingerprintAnswer(this.head, {this.unanswered = false});
}

/// mycelium: what the application calls.
abstract class DurableTransport {
  /// Deposit with three holders; the stream reports acknowledgements (0x91)
  /// and ends when two acknowledged or no holder is known.
  Stream<DepositEvent> deposit(int channel, Uint8List object);

  /// Ask a chosen holder about a fingerprint before the preview (0x97/0x98).
  Future<FingerprintAnswer> askFingerprint(int channel, Uint8List fingerprint);

  /// Edge: the user opened [channel] (phone: fetch what it lacks).
  void channelOpened(int channel);

  /// The other edges of §16.0 — start, network change, a new neighbour. The
  /// application calls it there and nowhere else; a collection the
  /// application starts for its own reasons (enrolment, recovery, the app
  /// opened) is no edge of this class.
  void edge();

  /// The holders a deposit would ask now (at most three, `address:port`);
  /// empty: no holder known, a deposit would only rest (§16.7 "the deposit
  /// is only an option once holders are known").
  List<String> depositHolders();
}
