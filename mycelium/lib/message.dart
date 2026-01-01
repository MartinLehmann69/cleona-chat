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
/// message, pair notice:     identifier 8 ‖ fixed neighbours ‖ content
/// acknowledgement (0x11):   identifier 8 ‖ fixed neighbours
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

  /// The envelope carried the sender's rotation chain (§4.5.4) — its
  /// receipt then tells the book the chain arrived (`anchor_book.dart`).
  bool carriedChain = false;

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
/// [origin] is `null` if the packet was fetched from a post box: then the
/// sender address is the HOLDER's, who cannot unseal a receipt (measured
/// 14.09.2026, `berichte/S384-QUITTUNG-BRIEFKASTEN.md`).
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

  /// The same for the mailbox of this identity: a day-key notice to a group
  /// pair counts as sent only with its receipt (§9.2, §8.2; S398 N-1a).
  void Function(Outbound)? onReceiptToMailbox;

  /// A receipt for no open outbound — after a restart the one the history
  /// still holds (§9.2, OP-30). [from] is the proven sender; the application
  /// decides, without it the receipt is discarded.
  void Function(Uint8List identifier, Address from)? onReceiptUnknown;

  /// The fixed neighbours this identity names to its contacts (D3,
  /// set in `host_codes.dart`) — sealed into every message and
  /// acknowledgement it sends.
  List<CardAddress> Function() ownNeighbours = () => const [];

  /// A peer's fixed neighbours came in a message or acknowledgement; [from]
  /// is the sender inside the seal. Empty lists are not reported.
  void Function(Address from, List<CardAddress> neighbours)? onNeighbours;

  /// Q1: the node keeps the way of a held-back copy ([onHeld], [origin] as
  /// fed) and sends its receipt that way ([heldBack]; `node_receipt.dart`).
  void Function(Uint8List identifier, CardAddress? origin)? onHeld;
  void Function(Uint8List identifier, void Function(CardAddress? origin) send)? heldBack;

  /// Q1 (§9.4, D-29): `true` holds the receipt of this copy back (asked
  /// before [onInbound]); the application sends it with [receiptSend].
  bool Function(Inbound)? receiptLater;

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
  /// With [kind] (a kind from `kinds.isPairNotice`) it is
  /// a pair notice: [content] goes out under this kind. An [identifier] still
  /// open is sent AGAIN (§9.3), sealed anew, on the [Outbound] its caller holds.
  Outbound ship(Uint8List content, Address to, CardAddress? destination,
      {Uint8List? identifier, int? kind}) {
    if (kind != null && !kinds.isPairNotice(kind)) {
      throw MessageError('not a pair notification: $kind');
    }
    final k = identifier ?? _roll(kIdentifierLength, _dice);
    final outbound = (_open[_key(k)] ?? Outbound(identifier: k, content: content, to: to))
      ..carriedChain = me.carriesChainTo(to);

    final envelope = Envelope.seal(
      plaintext: _head(k, content),
      recipient: to,
      sender: me,
    );

    _open[_key(k)] = outbound;
    // §9.1 (V11, S403): `in transit` begins only once a way demonstrably
    // carried the packet or a post box took it — until then it rests.
    report?.call('message ${_short(k)} on the ladder (${envelope.length} B)');
    send(_withKind(kind ?? kKindMessage, envelope), destination);
    return outbound;
  }

  /// Feeds in an incoming packet. [origin] is the address from which
  /// it came — `null` if it was fetched from a post box and the
  /// address thus belongs to the holder (see [Back]).
  void receive(Uint8List packet, CardAddress? origin) {
    if (packet.isEmpty) throw MessageError('empty packet');
    switch (packet[0]) {
      case kKindMessage:
        _messageCame(packet, origin);
      case kKindReceipt:
        _receiptCame(packet);
      case final s when kinds.isPairNotice(s):
        _messageCame(packet, origin, kind: s);
      default:
        throw MessageError('unexpected kind ${packet[0]}');
    }
  }

  void _messageCame(Uint8List packet, CardAddress? origin, {int? kind}) {
    final (plaintext, sender) = Envelope.unseal(
      envelope: Uint8List.sublistView(packet, 1),
      recipient: me,
    );
    final (identifier, content) = _cut(plaintext, sender);

    report?.call('Message ${_short(identifier)} arrived');
    final inbound = Inbound(
      identifier: identifier,
      content: content,
      from: sender,
      to: me.address,
      at: DateTime.now(),
      kind: kind,
    );
    final later = receiptLater?.call(inbound) ?? false;
    if (later) onHeld?.call(identifier, origin);
    onInbound(inbound);
    // Twin sync from an own device carries no acknowledgement (§9.2, D-37).
    if (!later && !sender.sameIdentity(me.address)) {
      receiptSend(identifier, sender, origin);
    }
  }

  /// The receipt (0x11) for [identifier] to [sender]; see [receiptLater].
  void receiptSend(Uint8List identifier, Address sender, [CardAddress? origin]) {
    // The receipt is sealed: otherwise a third party could forge it
    // and fake a tick to the sender that does not exist.
    final receipt = Envelope.seal(
      plaintext: _head(identifier, const []),
      recipient: sender,
      sender: me,
    );
    // Via the LADDER to the sender's IDENTITY, not to `origin` — for collected
    // post `origin` is the holder, who cannot unseal it. A held-back one
    // takes the way its message came ([heldBack], §9.2).
    final p = _withKind(kKindReceipt, receipt);
    final held = heldBack;
    if (held == null) return back(p, sender, origin);
    held(identifier, (o) => back(p, sender, o ?? origin));
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
      final late = onReceiptUnknown;
      report?.call('Receipt ${_short(identifier)} without open outbound '
          '— ${late == null ? 'discarded' : 'handed to the application'}');
      late?.call(identifier, sender);
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
    if (outbound.carriedChain) me.book.chainArrived(sender);
    _open.remove(_key(identifier));
    report?.call('message ${_short(identifier)} delivered');
    onReceipt?.call(outbound);
    onReceiptToMailbox?.call(outbound);
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
/// pair notice and acknowledgement (`0x11`): identifier ‖
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
