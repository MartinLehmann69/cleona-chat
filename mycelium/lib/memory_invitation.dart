/// The part of the memory that carries the issued invitations —
/// and the reader that both halves need.
///
/// ── WHY THIS FILE EXISTS ─────────────────────────────────────────
///
/// Until S384 an issued invitation survived no restart, and the
/// card is the only way by which a first contact comes about. The
/// document states it as a requirement: "The invitation list — code, expiry,
/// kind and its acceptance count, difficulty, label, revoked flag — is part
/// of the identity's backup" (`v42/kap/ch15.md:315-318`).
///
/// ── WHY NEXT TO `memory.dart` AND NOT IN IT ────────────────────
///
/// The cut is not the line count but the task: over there
/// stands WHAT is remembered restart-proof and how it is handled, here
/// stands ONE section of the file layout. Moved along are
/// [MemoryError] and [Reader], because Dart privacy applies per file and
/// both halves need them; `memory.dart` re-exports them.
///
/// ── FILE LAYOUT (the section this file encodes) ──────────────
/// ```
/// count (u16 big-endian)
/// per entry: code length (1 B) | code
///             | kind (1 B: 0 = single-use, 1 = open)
///             | expiry (u64, Unix seconds)
///             | difficulty (1 B)
///             | atMost (u16) | accepted (u16)
///             | revoked (1 B: 0 | 1)
///             | inPerson (1 B: 0 | 1)   — since version 7 (S388, ES-12)
///             | label: u16 length + UTF-8  — since version 10 (S390)
///             | requests: count (1 B)     — since version 9 (S389, E-1)
///               per request: who (Address.length)
///                         | origin: type (1 B: 4 | 6) | address (4 | 16)
///                                | port (u16)
///                         | arrived (u64, milliseconds)
///                         | introduction: u16 length + bytes (0 = none)
///                         | neighbour, answer code — since version 14,
///                           layout in `memory_request.dart`
///             | card neighbour: flag (1 B) | address — since version 15
///               (S394 V6: the neighbour the card named)
/// ```
///
/// The waiting requests stand IN the entry of their invitation: §15.4 limits
/// them per invitation, the revocation takes them along, and the order IS the
/// displacement order. The kind is mapped instead of written as `index`:
/// otherwise a reordered enum in
/// `invitation.dart` would silently change the file format.
///
/// The **label** (`ch15.md:315`, §15.3 "Attribution") has been included since S390:
/// until then `invitation.dart` had no such field, and so there was
/// nothing to write.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:mycelium/invitation.dart' as inv;
import 'package:mycelium/memory_request.dart';
import 'package:mycelium/card_address.dart'
    show CardAddress, CardFormatError, optionalAddressRead, optionalAddressWrite;

/// The file is there, but unusable: wrong key, truncated,
/// unknown version, bent bytes. Thrown from `Memory.open`
/// BEFORE the return — there is never a half instance.
class MemoryError implements Exception {
  final String reason;
  MemoryError(this.reason);
  @override
  String toString() => 'GedaechtnisFehler: $reason';
}

/// Reads a byte bundle with a running pointer; throws [MemoryError]
/// as soon as fewer bytes are there than needed.
class Reader {
  final Uint8List _b;
  int _i = 0;
  Reader(this._b);

  int get _rest => _b.length - _i;

  void _check(int n) {
    if (_rest < n) {
      throw MemoryError('File too short: $n B needed, $_rest B present');
    }
  }

  int byte() {
    _check(1);
    return _b[_i++];
  }

  Uint8List bytes(int n) {
    _check(n);
    final r = Uint8List.fromList(_b.sublist(_i, _i + n));
    _i += n;
    return r;
  }

  int u16() {
    _check(2);
    final v = ByteData.sublistView(_b, _i, _i + 2).getUint16(0, Endian.big);
    _i += 2;
    return v;
  }

  int u32() {
    _check(4);
    final v = ByteData.sublistView(_b, _i, _i + 4).getUint32(0, Endian.big);
    _i += 4;
    return v;
  }

  int u64() {
    _check(8);
    final v = ByteData.sublistView(_b, _i, _i + 8).getUint64(0, Endian.big);
    _i += 8;
    return v;
  }

  void done() {
    if (_rest != 0) {
      throw MemoryError('$_rest surplus bytes at the end');
    }
  }
}

/// An issued invitation as it lies on disk: exactly the
/// values that `inv.Invitation` carries, and not a byte more.
///
/// Only the format — in operation every invitation lives as `inv.Invitation`:
/// [invitationFromRemembered] makes one from it at start, [rememberedFrom]
/// writes it back. Until S388 this bundle stayed after loading
/// — without revocation and without answer (B3).
typedef RememberedInvitation = ({
  Uint8List code,
  inv.Kind kind,
  int expiryUnixSeconds,
  int difficulty,
  int atMost,
  int accepted,
  bool revoke,
  bool inPerson,
  String label,
  List<inv.WaitingRequest> requests,
  CardAddress? cardNeighbour,
});

/// The values of a living invitation as they go to disk.
RememberedInvitation rememberedFrom(inv.Invitation e) => (
      code: e.code,
      kind: e.kind,
      expiryUnixSeconds: e.expiryUnixSeconds,
      difficulty: e.difficulty,
      atMost: e.atMost,
      accepted: e.accepted,
      revoke: e.revoke,
      inPerson: e.inPerson,
      label: e.label,
      requests: e.requests.all,
      cardNeighbour: e.cardNeighbour,
    );

/// The living invitation for a remembered entry — the path at start.
inv.Invitation invitationFromRemembered(RememberedInvitation g) =>
    inv.Invitation.outSplit(
      code: g.code,
      kind: g.kind,
      expiryUnixSeconds: g.expiryUnixSeconds,
      difficulty: g.difficulty,
      atMost: g.atMost,
      accepted: g.accepted,
      revoke: g.revoke,
      inPerson: g.inPerson,
      label: g.label,
      waitingRequests: g.requests,
      cardNeighbour: g.cardNeighbour,
    );

/// How many invitations lie on disk at most.
///
/// **SUGGESTION, not a default from the document.** `ch15.md:303` caps the
/// STANDING invitations at ten (`inv.kAtMostStanding`); for the
/// SAVED list the document names no number. It is longer because
/// revoked ones (`ch15.md:322-324`) and expired ones within the grace period
/// go along. Twenty = ten standing plus ten expiring; cutting off
/// happens at the back, and `Identity.invitationsSave` puts those still
/// accepting in front.
const int kAtMostRemembered = 20;

/// Is time past this invitation — expiry PLUS grace period? Whoever
/// already cuts off at the expiry on loading takes from the grace period exactly the
/// case for which it exists (a request that lay seven days in the
/// post box, `invitation.dart` `kGracePeriodDays`).
bool timeOver(RememberedInvitation e, int now) =>
    now > e.expiryUnixSeconds + inv.kGracePeriodSeconds;

/// Is it used up? For [inv.Kind.singleUse] after the first
/// accepted request (`hoechstens` is 1 there), for [inv.Kind.open]
/// after the `hoechstens`-th.
bool exhausted(RememberedInvitation e) => e.accepted >= e.atMost;

/// Does the issuer still accept a request for this invitation? The same
/// question as `inv.Invitation.acceptanceWindowOpenAt`, only on the bundle.
bool stillAccepts(RememberedInvitation e, int now) =>
    !e.revoke && !timeOver(e, now) && !exhausted(e);

/// Writes at most [kAtMostRemembered] entries in the given
/// order; what goes beyond that falls off at the back.
Uint8List invitationsEncode(Iterable<RememberedInvitation> list) {
  final taken = list.take(kAtMostRemembered).toList();
  final b = BytesBuilder();
  b.add(_u16(taken.length));
  for (final e in taken) {
    if (e.code.isEmpty || e.code.length > 255) {
      throw ArgumentError('Code must be 1..255 B, was ${e.code.length}');
    }
    if (e.difficulty < 0 || e.difficulty > 255) {
      throw ArgumentError('Difficulty must be 0..255, was '
          '${e.difficulty}');
    }
    if (e.atMost < 1 || e.atMost > 65535) {
      throw ArgumentError('atMost must be 1..65535, was '
          '${e.atMost}');
    }
    if (e.accepted < 0 || e.accepted > 65535) {
      throw ArgumentError('accepted must be 0..65535, was '
          '${e.accepted}');
    }
    if (e.expiryUnixSeconds < 0) {
      throw ArgumentError('Expiry must not be negative, was '
          '${e.expiryUnixSeconds}');
    }
    b.addByte(e.code.length);
    b.add(e.code);
    b.addByte(_kindByte(e.kind));
    b.add(_u64(e.expiryUnixSeconds));
    b.addByte(e.difficulty);
    b.add(_u16(e.atMost));
    b.add(_u16(e.accepted));
    b.addByte(e.revoke ? 1 : 0);
    b.addByte(e.inPerson ? 1 : 0);
    final label = utf8.encode(e.label);
    if (label.length > inv.kLabelAtMostBytes) {
      throw ArgumentError('label ${label.length} B, at most '
          '${inv.kLabelAtMostBytes} are allowed');
    }
    b.add(_u16(label.length));
    b.add(label);
    requestsEncode(b, e.requests); // `gedaechtnis_anfrage.dart`
    optionalAddressWrite(b, e.cardNeighbour);
  }
  return b.toBytes();
}

/// Reads the section back and leaves lying what can no longer
/// accept a request anyway.
///
/// **What does NOT come back:** expiry including grace period past ([timeOver])
/// — otherwise an invitation would become immortal by its issuer
/// restarting often; and used up ([exhausted]) — a single-use
/// invitation must not be redeemable again after a restart.
///
/// **What comes back although it no longer accepts anything:** the revoked ones.
/// `ch15.md:322-324` wants them visible so that the user can revoke
/// again. [stillAccepts] says no to them, that suffices.
List<RememberedInvitation> invitationsDecode(
  Uint8List bytes, {
  required int now,
}) {
  final l = Reader(bytes);
  final count = l.u16();
  if (count > kAtMostRemembered) {
    throw MemoryError('$count remembered invitations, at most '
        '$kAtMostRemembered are provided');
  }
  final out = <RememberedInvitation>[];
  for (var i = 0; i < count; i++) {
    final codeLength = l.byte();
    if (codeLength == 0) throw MemoryError('Code of length 0');
    final code = l.bytes(codeLength);
    final kind = _kindFromByte(l.byte());
    final expiry = l.u64();
    final difficulty = l.byte();
    final atMost = l.u16();
    if (atMost == 0) {
      throw MemoryError('atMost 0 is not an invitation');
    }
    final accepted = l.u16();
    final revokeByte = l.byte();
    if (revokeByte > 1) {
      throw MemoryError('invalid revoke flag $revokeByte');
    }
    final inPersonByte = l.byte();
    if (inPersonByte > 1) {
      throw MemoryError('invalid in-person flag $inPersonByte');
    }
    final label = _labelRead(l);
    final requests = requestsDecode(l);
    final CardAddress? cardNeighbour;
    try {
      cardNeighbour = optionalAddressRead(l.bytes, 'card neighbour');
    } on CardFormatError catch (e) {
      throw MemoryError('card neighbour: $e');
    }
    // The selection takes effect AFTER the complete reading of the entry: a
    // passed-over entry is not skipped — the pointer must stand
    // exactly behind it, otherwise the next one falls apart.
    final e = (
      code: code,
      kind: kind,
      expiryUnixSeconds: expiry,
      difficulty: difficulty,
      atMost: atMost,
      accepted: accepted,
      revoke: revokeByte == 1,
      inPerson: inPersonByte == 1,
      label: label,
      requests: requests,
      cardNeighbour: cardNeighbour,
    );
    if (timeOver(e, now) || exhausted(e)) continue;
    out.add(e);
  }
  l.done();
  return out;
}

/// Reads the label (§15.3 "Attribution"). Too long or not UTF-8 means:
/// the file is bent — then an error is the answer, not a substitute value.
String _labelRead(Reader l) {
  final b = l.bytes(l.u16());
  if (b.length > inv.kLabelAtMostBytes) {
    throw MemoryError('label ${b.length} B, at most '
        '${inv.kLabelAtMostBytes} are allowed');
  }
  try {
    return utf8.decode(b);
  } on FormatException catch (e) {
    throw MemoryError('Label is not UTF-8: ${e.message}');
  }
}

int _kindByte(inv.Kind a) => switch (a) {
      inv.Kind.singleUse => 0,
      inv.Kind.open => 1,
    };

inv.Kind _kindFromByte(int b) => switch (b) {
      0 => inv.Kind.singleUse,
      1 => inv.Kind.open,
      _ => throw MemoryError('unknown kind $b'),
    };

Uint8List _u16(int v) =>
    (ByteData(2)..setUint16(0, v, Endian.big)).buffer.asUint8List();
Uint8List _u64(int v) =>
    (ByteData(8)..setUint64(0, v, Endian.big)).buffer.asUint8List();
