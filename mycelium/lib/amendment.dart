import 'dart:convert';
import 'dart:typed_data';

import 'package:mycelium/first_contact.dart' show Report;
import 'package:mycelium/card.dart';
import 'package:mycelium/message.dart' show Back, kIdentifierLength;
import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/envelope.dart';

/// Amendments to a message that already exists — reaction,
/// edit, read mark.
///
/// All three carry the identifier of the message to which they refer,
/// and take the same sealed path as the message itself. A
/// third party cannot forge any of them: the envelope says who
/// closed it.
///
/// ── A READ MARK IS NOT A DELIVERY STATE ───────────────────────────
/// There are four delivery states — resting, in transit, delivered,
/// failed — and that is how it stays. "Read" is not a fifth: it
/// answers a different question. Delivered means the device has it;
/// read means a human has looked. A read mark that never
/// comes is therefore also not a delivery error — the message has
/// arrived, it just was not looked at, or the recipient
/// sends none as a matter of principle. The mark therefore hangs as its own
/// point in time on the outgoing message and not on its state.
///
/// ── WHO MAY DO WHAT ──────────────────────────────────────────────────────
/// Anyone who has received the message may react. **Only the one who wrote it
/// may edit it** — otherwise a recipient could
/// put words in the sender's mouth afterwards that would stand on the sender's
/// side as the sender's own. This file cannot know that by itself;
/// it asks the caller via [authorFrom], who holds the
/// history. If it answers `null`, the edit is discarded — when in
/// doubt, do not change.
///
/// ── THE WINDOW ───────────────────────────────────────────────────────
/// An edit applies only within [kEditWindow] after the
/// point in time of the original message, and **checked by the
/// recipient**. A deadline that only the sender checks is none: whoever
/// changes the sender code has none any more.
///
/// This file knows no network. It gets a function for sending and
/// is fed with incoming packets.

/// How long after sending an edit still applies.
const Duration kEditWindow = Duration(minutes: 60);

/// Length of the effect byte before the content of a reaction.
const int kEffectLength = 1;

// Deliberately decimal: this is NOT a packet kind, but a marker byte
// INSIDE the payload, behind the seal. Packet kinds stand
// exclusively in kinds.dart and are written there as 0x.. —
// keeping the two notations apart makes visible in code
// what kind of number one is looking at.
const int _kSet = 0;
const int _kTake = 1;

/// Maximum length of a reaction in bytes. A reaction is a
/// symbol, not a second message path.
const int kReactionMaxLength = 32;

class AmendmentError implements Exception {
  final String reason;
  AmendmentError(this.reason);
  @override
  String toString() => 'NachtragFehler: $reason';
}

/// A received reaction.
class Reaction {
  /// The message to which it refers.
  final Uint8List identifier;
  final String chars;
  final Address from;

  /// The receiving identity — as [Inbound.to] (`message.dart`).
  final Address to;

  /// `false` means: the same reaction was withdrawn.
  final bool isSet;
  final DateTime at;

  Reaction({
    required this.identifier,
    required this.chars,
    required this.from,
    required this.to,
    required this.isSet,
    required this.at,
  });
}

/// A received edit — the content of a known message
/// was changed by its author.
class Edit {
  final Uint8List identifier;

  /// The new content, raw. As with a message this layer does not
  /// interpret it (see `message.dart`); only the reaction below it is
  /// still text, because by construction it is a symbol.
  final Uint8List newContent;
  final Address from;

  /// The receiving identity — as [Inbound.to] (`message.dart`).
  final Address to;
  final DateTime at;

  Edit({
    required this.identifier,
    required this.newContent,
    required this.from,
    required this.to,
    required this.at,
  });
}

/// A received read mark for an own message.
class ReadMark {
  final Uint8List identifier;
  final Address from;

  /// The receiving identity — as [Inbound.to] (`message.dart`).
  final Address to;
  final DateTime at;

  ReadMark(
      {required this.identifier,
      required this.from,
      required this.to,
      required this.at});
}

/// Answers who wrote a known message, and when.
/// `null` if the message is unknown.
typedef AuthorFrom = ({Address who, DateTime at})? Function(
    Uint8List identifier);

/// The amendment path. Holds no history — that lies with the caller.
class Amendments {
  final PostBox me;
  /// An amendment takes the same path as a message — via the
  /// ladder, only without expecting a receipt itself. Therefore [Back]
  /// and not [Send]: the ladder needs the IDENTITY of the
  /// recipient, not merely a network address.
  ///
  /// Measured on 14.09.2026: with [Send] every amendment took the
  /// direct branch of `_viaLadder` and NEVER used the ladder — no
  /// post box, no forwarding, no retrying. A reaction to
  /// a message to someone who was off at the moment was thus lost.
  final Back send;
  final Report? report;

  /// Who wrote the message with this identifier, and when.
  final AuthorFrom authorFrom;

  final void Function(Reaction)? onReaction;
  final void Function(Edit)? onEdit;
  final void Function(ReadMark)? onReadMark;

  Amendments({
    required this.me,
    required this.send,
    required this.authorFrom,
    this.onReaction,
    this.onEdit,
    this.onReadMark,
    this.report,
  });

  /// Reacts to the message [identifier] with [chars].
  /// [isSet] `false` withdraws the same reaction.
  void react(Uint8List identifier, String chars, Address to,
      CardAddress destination,
      {bool isSet = true}) {
    _identifierCheck(identifier);
    final z = utf8.encode(chars);
    if (z.isEmpty) throw AmendmentError('empty reaction');
    if (z.length > kReactionMaxLength) {
      throw AmendmentError('reaction ${z.length} B, at most '
          '$kReactionMaxLength B');
    }
    final b = BytesBuilder()
      ..add(identifier)
      ..addByte(isSet ? _kSet : _kTake)
      ..add(z);
    _send(kinds.kReaction, b.toBytes(), to, destination);
    report?.call('Reaction to ${_short(identifier)} '
        '${isSet ? 'set' : 'withdrawn'}');
  }

  /// Changes the content of the OWN message [identifier].
  ///
  /// [newContent] goes out unchanged — arbitrary bytes.
  ///
  /// Whether the deadline is still running is also checked by the recipient; it stands here
  /// so that a hopeless attempt does not cost network in the first place.
  void edit(Uint8List identifier, Uint8List newContent, Address to,
      CardAddress destination) {
    _identifierCheck(identifier);
    final author = authorFrom(identifier);
    if (author == null) {
      throw AmendmentError('Message ${_short(identifier)} is unknown');
    }
    if (!author.who.sameIdentity(me.address)) {
      throw AmendmentError('Message ${_short(identifier)} is not our own');
    }
    if (DateTime.now().difference(author.at) > kEditWindow) {
      throw AmendmentError('Edit deadline for ${_short(identifier)} '
          'has expired');
    }
    final b = BytesBuilder()
      ..add(identifier)
      ..add(newContent);
    _send(kinds.kEdit, b.toBytes(), to, destination);
    report?.call('Edit of ${_short(identifier)} in transit');
  }

  /// Notes to the sender that [identifier] has been read.
  ///
  /// Voluntary: whoever does not want this does not call it. There is no
  /// state that would stay open because of it.
  void read(Uint8List identifier, Address to, CardAddress destination) {
    _identifierCheck(identifier);
    _send(kinds.kReadMark, Uint8List.fromList(identifier), to, destination);
    report?.call('Read mark for ${_short(identifier)} in transit');
  }

  /// Feeds in an arriving packet.
  void receive(Uint8List packet, CardAddress origin) {
    if (packet.isEmpty) throw AmendmentError('empty packet');
    final (plaintext, sender) = Envelope.unseal(
      envelope: Uint8List.sublistView(packet, 1),
      recipient: me,
    );
    if (plaintext.length < kIdentifierLength) {
      throw AmendmentError('Amendment without identifier');
    }
    final identifier = Uint8List.fromList(
        Uint8List.sublistView(plaintext, 0, kIdentifierLength));
    final rest = Uint8List.sublistView(plaintext, kIdentifierLength);

    switch (packet[0]) {
      case kinds.kReaction:
        _reactionCame(identifier, rest, sender);
      case kinds.kEdit:
        _editCame(identifier, rest, sender);
      case kinds.kReadMark:
        _readMarkCame(identifier, rest, sender);
      default:
        throw AmendmentError('unexpected kind ${packet[0]}');
    }
  }

  void _reactionCame(Uint8List identifier, Uint8List rest, Address from) {
    if (rest.length < kEffectLength + 1) {
      throw AmendmentError('Reaction without emoji');
    }
    final isSet = rest[0] == _kSet;
    final chars = utf8.decode(Uint8List.sublistView(rest, kEffectLength));
    report?.call('Reaction "$chars" to ${_short(identifier)} arrived');
    onReaction?.call(Reaction(
      identifier: identifier,
      chars: chars,
      from: from,
      to: me.address,
      isSet: isSet,
      at: DateTime.now(),
    ));
  }

  void _editCame(Uint8List identifier, Uint8List rest, Address from) {
    // Only the author may change — otherwise a recipient would put words
    // in the sender's mouth that would stand on the sender's side as the sender's
    // own.
    final author = authorFrom(identifier);
    if (author == null) {
      report?.call('Edit for unknown message '
          '${_short(identifier)} — discarded');
      return;
    }
    if (!author.who.sameIdentity(from)) {
      report?.call('Edit of ${_short(identifier)} did not come from the '
          'author — discarded');
      return;
    }
    if (DateTime.now().difference(author.at) > kEditWindow) {
      report?.call('Edit of ${_short(identifier)} came after expiry '
          'of the deadline — discarded');
      return;
    }
    report?.call('Edit of ${_short(identifier)} arrived');
    onEdit?.call(Edit(
      identifier: identifier,
      // Copy, not view: `rest` lies in the plaintext buffer of the
      // unsealed envelope.
      newContent: Uint8List.fromList(rest),
      from: from,
      to: me.address,
      at: DateTime.now(),
    ));
  }

  void _readMarkCame(Uint8List identifier, Uint8List rest, Address from) {
    if (rest.isNotEmpty) {
      throw AmendmentError('Read mark with ${rest.length} B attachment');
    }
    // Reading can only be confirmed by whoever received the message — i.e.
    // NOT its author. If the mark comes back from ourselves, something
    // is wrong, and a tick would be a lie.
    final author = authorFrom(identifier);
    if (author == null) {
      report?.call('Read mark for unknown message '
          '${_short(identifier)} — discarded');
      return;
    }
    if (!author.who.sameIdentity(me.address)) {
      report?.call('Read mark for a foreign message '
          '${_short(identifier)} — discarded');
      return;
    }
    report?.call('Read mark for ${_short(identifier)} arrived');
    onReadMark?.call(
        ReadMark(
            identifier: identifier, from: from, to: me.address, at: DateTime.now()));
  }

  void _send(int kind, Uint8List plaintext, Address to,
      CardAddress destination) {
    final envelope = Envelope.seal(
      plaintext: plaintext,
      recipient: to,
      sender: me,
    );
    final p = Uint8List(1 + envelope.length);
    p[0] = kind;
    p.setRange(1, p.length, envelope);
    send(p, to, destination);
  }

  void _identifierCheck(Uint8List k) {
    if (k.length != kIdentifierLength) {
      throw AmendmentError('Identifier must be $kIdentifierLength B, '
          'was ${k.length}');
    }
  }
}

String _short(Uint8List k) =>
    k.take(3).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
