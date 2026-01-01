import 'dart:math';
import 'dart:typed_data';

import 'package:mycelium/first_contact.dart' show Report;
import 'package:mycelium/card.dart';
import 'package:mycelium/envelope.dart';
import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/neighbour_list.dart';

/// A message via an existing contact — two packets.
///
/// ```
/// ALICE                                   BOB
///  (0x10) message     ---------------->   unseals, displays
///                     <----------------   (0x11) delivery receipt
///  tick at the sender
/// ```
///
/// This file knows no network. It gets a function for sending and
/// is fed with incoming packets.
///
/// ── IT CARRIES BYTES, IT DOES NOT INTERPRET THEM ───────────────────────────
/// The content is a [Uint8List] and nothing else. Until S385 it was a
/// [String]: `ship` did `utf8.encode`, the inbound `utf8.decode`.
/// Thus this layer could only carry what is valid UTF-8 — but the
/// application above sends protobuf frames, and a `utf8.decode`
/// on them throws. Whoever wants to send text encodes it ABOVE, at exactly one
/// place (`MailboxOutbound.sendText`).
///
/// There is deliberately NO byte here that says what the content is. The
/// application brings its own typing; a second one here would be
/// a second truth that at some point deviates from the first.
///
/// ── THE SEALED PLAINTEXT ───────────────────────────────────────────────────
/// ```
/// message, publication, pair notice:  identifier 8 ‖ fixed neighbours ‖ content (or mode 1)
/// acknowledgement (0x11):              identifier 8 ‖ fixed neighbours
/// ```
/// "Fixed neighbours" is the list of `neighbour_list.dart` (count 0..3 +
/// addresses, ≤ 58 B): the sender's fixed neighbours as its identity names
/// them to contacts (D3). A contact learns them only here, sealed — a
/// change costs no packet of its own (proposal "contacts as fixed
/// neighbours", rule 5, 6.9; §9.2). The list stands BEHIND the identifier,
/// so every kind keeps its first 8 bytes, and IN FRONT of the content,
/// because the content is the application's bytes of any length and has no
/// end marker a trailing list could hang on.
enum DeliveryState {
  /// rests at the sender, not yet out
  resting,

  /// gone out, no receipt yet
  inTransit,

  /// the recipient has receipted
  delivered,

  /// given up — no route has carried
  failed,
}

const int kKindMessage = kinds.kMessage;
const int kKindReceipt = kinds.kDeliveryReceipt;
const int kKindPublication = kinds.kKeyRotation;

/// Mode of a publication: identifier and routes continue to apply. mycelium has no
/// tags; the only thing a contact could derive anew is the identifier,
/// and that stays the same across the routine rotation.
const int kModeRoutesApplyFurther = kinds.kModeRoutesApplyFurther;

/// Identifier of a message: 8 bytes, drawn randomly by the sender.
const int kIdentifierLength = 8;

class MessageError implements Exception {
  final String reason;
  MessageError(this.reason);
  @override
  String toString() => 'NachrichtFehler: $reason';
}

/// An outgoing message as the sender sees it.
class Outbound {
  final Uint8List identifier;

  /// The payload, unchanged. See file header: this layer does not interpret
  /// it.
  final Uint8List content;
  final Address to;
  DeliveryState state;
  DateTime? acknowledgedAt;

  Outbound({
    required this.identifier,
    required this.content,
    required this.to,
    this.state = DeliveryState.resting,
  });
}

/// A received message as the recipient sees it.
/// How an ANSWER goes to the sender — the delivery receipt.
///
/// Separate from [Out] because it answers a different question. [Out]
/// names only the packet and an address suggestion; here the IDENTITY
/// of the recipient stands in front, and [origin] is only a suggestion for the first
/// route.
///
/// [origin] is `null` if the packet was fetched from a post box:
/// then the sender address belongs to the HOLDER, not the sender.
/// Measured on 14.09.2026 (`berichte/S384-QUITTUNG-BRIEFKASTEN.md`): until
/// then the receipt went to exactly this address, the holder could not
/// unseal it and discarded it — the sender NEVER learned that
/// delivery had happened.
typedef Back = void Function(
    Uint8List packet, Address to, CardAddress? origin);

/// The way out for an OWN message.
///
/// [destination] is the SUGGESTION for the first ladder step and may be `null`.
/// That is no convenience but §8.2: the post box depends
/// on the OWN neighbours, not on an address of the recipient
/// (`node.dart`, `inPostBox` gets only `target.identifier`). Until S390
/// this parameter was not nullable, and the mailbox's outbound therefore returned
/// without an address BEFORE the ladder was entered at all —
/// step 4 was unreachable exactly in the case for which §8.2 provides it
/// (`berichte/S390-EVAL-NACHRICHT.md`, finding B-2).
typedef Out = void Function(Uint8List packet, CardAddress? destination);

class Inbound {
  final Uint8List identifier;

  /// The payload, unchanged — byte by byte what the sender passed.
  final Uint8List content;
  final Address from;

  /// The RECEIVING identity — the one whose key opened the seal.
  /// A node carries several; without this field the
  /// caller did not know which mailbox the inbound belongs to (S385, W1.c).
  final Address to;
  final DateTime at;

  /// `null` for a message. Set for a PUBLICATION (0x15): then
  /// [content] is empty, and the only thing that counts is the address in
  /// [from] — no display, no history entry.
  final int? mode;

  /// `null` for a message. Set for a PAIR NOTICE
  /// (`kinds.isPairNotice`): then it is the kind, [content] its
  /// payload — no display, no history entry (`mailbox_pair.dart`).
  final int? kind;

  Inbound({
    required this.identifier,
    required this.content,
    required this.from,
    required this.to,
    required this.at,
    this.mode,
    this.kind,
  });
}

/// The message path. Holds the open outbounds so that a receipt
/// can be assigned — there is no more state here.
class Messages {
  final PostBox me;
  final Out send;

  /// The way back for the delivery receipt. See [Back].
  final Back back;
  final Report? report;
  final Random _dice;

  /// Called when a message has arrived.
  final void Function(Inbound) onInbound;

  /// Called when an own message has been receipted.
  final void Function(Outbound)? onReceipt;

  /// The fixed neighbours this identity names to its contacts (D3,
  /// set in `host_codes.dart`) — sealed into every message and
  /// acknowledgement it sends.
  List<CardAddress> Function() ownNeighbours = () => const [];

  /// A peer's fixed neighbours came in a message or acknowledgement; [from]
  /// is the sender inside the seal. Empty lists are not reported.
  void Function(Address from, List<CardAddress> neighbours)? onNeighbours;

  final Map<String, Outbound> _open = {};

  Messages({
    required this.me,
    required this.send,
    required this.back,
    required this.onInbound,
    this.onReceipt,
    this.report,
    Random? dice,
  }) : _dice = dice ?? Random.secure();

  /// Open outbounds — those whose receipt is still awaited.
  Iterable<Outbound> get open => _open.values;

  /// Sends [content] to [to]. [destination] is the suggestion for the first
  /// ladder step and may be `null` — see [Out].
  ///
  /// [content] goes out unchanged — arbitrary bytes, including ones that
  /// are not valid UTF-8.
  ///
  /// With [mode] it is a publication (0x15): [content] is not
  /// sent, the plaintext is identifier ‖ mode. It is receipted like every
  /// message. With [kind] (a kind from `kinds.isPairNotice`) it is
  /// a pair notice: [content] goes out under this kind.
  Outbound ship(Uint8List content, Address to, CardAddress? destination,
      {Uint8List? identifier, int? mode, int? kind}) {
    if (kind != null && (mode != null || !kinds.isPairNotice(kind))) {
      throw MessageError('not a pair notification: $kind');
    }
    final k = identifier ?? _roll(kIdentifierLength, _dice);
    final outbound = Outbound(identifier: k, content: content, to: to);

    final envelope = Envelope.seal(
      plaintext: _head(k, mode == null ? content : [mode]),
      recipient: to,
      sender: me,
    );

    _open[_key(k)] = outbound;
    outbound.state = DeliveryState.inTransit;
    report?.call('message ${_short(k)} in transit (${envelope.length} B)');
    send(_withKind(kind ?? (mode == null ? kKindMessage : kKindPublication),
        envelope), destination);
    return outbound;
  }


  /// Feeds in an incoming packet. [origin] is the address from which
  /// it came — `null` if it was fetched from a post box and the
  /// address thus belongs to the holder (see [Back]).
  void receive(Uint8List packet, CardAddress? origin) {
    if (packet.isEmpty) throw MessageError('empty packet');
    switch (packet[0]) {
      case kKindMessage:
        _messageCame(packet, origin, announcement: false);
      case kKindPublication:
        _messageCame(packet, origin, announcement: true);
      case kKindReceipt:
        _receiptCame(packet);
      case final s when kinds.isPairNotice(s):
        _messageCame(packet, origin, announcement: false, kind: s);
      default:
        throw MessageError('unexpected kind ${packet[0]}');
    }
  }

  void _messageCame(Uint8List packet, CardAddress? origin,
      {required bool announcement, int? kind}) {
    final (plaintext, sender) = Envelope.unseal(
      envelope: Uint8List.sublistView(packet, 1),
      recipient: me,
    );
    final (identifier, content) = _cut(plaintext, sender);
    if (announcement && content.length != 1) {
      throw MessageError('Announcement with ${content.length} B instead of mode');
    }

    report?.call('${announcement ? 'Announcement' : 'Message'} '
        '${_short(identifier)} arrived');
    onInbound(Inbound(
      identifier: identifier,
      content: announcement ? Uint8List(0) : content,
      from: sender,
      to: me.address,
      at: DateTime.now(),
      mode: announcement ? content[0] : null,
      kind: kind,
    ));

    // The receipt is sealed: otherwise a third party could forge it
    // and fake a tick to the sender that does not exist.
    final receipt = Envelope.seal(
      plaintext: _head(identifier, const []),
      recipient: sender,
      sender: me,
    );
    // via the LADDER, not to `origin`. For a piece fetched from the post box
    // `origin` belongs to the holder; it cannot unseal the receipt
    // and discards it. It therefore goes to the
    // IDENTITY of the sender, and `origin` is only the suggestion for the
    // first step — for a message arriving directly that is
    // still the fastest route.
    back(_withKind(kKindReceipt, receipt), sender, origin);
  }

  void _receiptCame(Uint8List packet) {
    final (plaintext, sender) = Envelope.unseal(
      envelope: Uint8List.sublistView(packet, 1),
      recipient: me,
    );
    final (identifier, rest) = _cut(plaintext, sender);
    if (rest.isNotEmpty) {
      throw MessageError('Receipt with ${rest.length} B after the list');
    }
    final outbound = _open[_key(identifier)];
    if (outbound == null) {
      report?.call('Receipt ${_short(identifier)} without open outbound '
          '— discarded');
      return;
    }
    // Only the one to whom the message went may receipt — the IDENTITY, not
    // the KEM generation: whoever rotated between sending and receipting
    // receipts with a new address (S385, E1).
    if (!sender.sameIdentity(outbound.to)) {
      report?.call('Receipt ${_short(identifier)} from someone else '
          '— discarded');
      return;
    }
    outbound.state = DeliveryState.delivered;
    outbound.acknowledgedAt = DateTime.now();
    _open.remove(_key(identifier));
    report?.call('message ${_short(identifier)} delivered');
    onReceipt?.call(outbound);
  }

  /// identifier ‖ own fixed neighbours ‖ [rest] — see the file header.
  Uint8List _head(Uint8List identifier, List<int> rest) =>
      messagePlaintext(identifier, ownNeighbours(), rest);

  /// Counterpart to [_head]: identifier and the rest (a copy — a view would
  /// keep the unsealed buffer alive); the list goes to [onNeighbours].
  (Uint8List, Uint8List) _cut(Uint8List plaintext, Address sender) {
    var pos = 0;
    Uint8List read(int n) {
      if (pos + n > plaintext.length) {
        throw MessageError('plaintext too short (${plaintext.length} B)');
      }
      return Uint8List.sublistView(plaintext, pos, pos += n);
    }

    final identifier = Uint8List.fromList(read(kIdentifierLength));
    final List<CardAddress> list;
    try {
      list = neighbourListRead(read, 'fixed neighbours');
    } on CardFormatError catch (e) {
      throw MessageError('$e');
    }
    if (list.isNotEmpty) onNeighbours?.call(sender, list);
    return (identifier, Uint8List.fromList(Uint8List.sublistView(plaintext, pos)));
  }

  /// No route has carried — the caller gives up.
  void giveUp(Uint8List identifier) {
    final a = _open.remove(_key(identifier));
    if (a == null) return;
    a.state = DeliveryState.failed;
    report?.call('message ${_short(identifier)} failed');
  }
}

/// The sealed plaintext of every kind this file sends — message,
/// publication, pair notice and acknowledgement (`0x11`): identifier ‖
/// [neighbours] ‖ [rest] (file header). The ONE place that lays it out;
/// whoever builds such a plaintext outside [Messages] builds it here.
Uint8List messagePlaintext(
    Uint8List identifier, List<CardAddress> neighbours, List<int> rest) {
  final b = BytesBuilder()..add(identifier);
  neighbourListWrite(b, neighbourListClean(neighbours));
  return (b..add(rest)).toBytes();
}

Uint8List _withKind(int kind, Uint8List rest) {
  final b = Uint8List(1 + rest.length);
  b[0] = kind;
  b.setRange(1, b.length, rest);
  return b;
}

String _key(Uint8List k) => k.join(',');

String _short(Uint8List k) =>
    k.take(3).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List _roll(int n, Random r) {
  final b = Uint8List(n);
  for (var i = 0; i < n; i++) {
    b[i] = r.nextInt(256);
  }
  return b;
}
