/// The buffer of the waiting requests — and the two numbers from §15.4.
///
/// ── WHY THIS FILE EXISTS ─────────────────────────────────────────
///
/// A received, not yet answered request was gone after a
/// restart (E-1, measured in `berichte/S388-BAU-EINLADUNG.md` §7:
/// "waiting before the restart: 1, afterwards: 0"). With it the QUESTION to the
/// user was lost (§12.5), and the requester never got an answer —
/// it does not send again. So the buffer must be saved along, and
/// WITH the invitation: §15.4 counts "at most 20 per invitation", the
/// displacement order belongs to the invitation, and a second storage
/// would be a second place where the same state can diverge
/// (exactly the error B2/B4 that S388 closed).
///
/// ── WHY NEXT TO `invitation.dart` AND NOT IN IT ──────────────────────
///
/// The same as with `memory_invitation.dart`: the line budget of 400
/// (`mycelium/README.md`) has no exception mechanism, and `invitation.dart`
/// stood at 328. But the cut is not the line count but the
/// task: over there stands what the issuer KNOWS about its invitation
/// (kind, counter, expiry, revocation), here stands what WAITS on it.
/// `invitation.dart` re-exports this file — for every existing
/// caller nothing changes.
library;

import 'dart:typed_data';

import 'package:mycelium/address.dart';
import 'package:mycelium/card_address.dart';
import 'package:mycelium/introduction.dart';

/// At most this many waiting requests per invitation (§15.4, §15.12).
/// Stood in `first_contact_invitation.dart` until S389 and is still
/// re-exported from there; the number belongs to the buffer, and the buffer lies here.
const int kBufferPerInvitation = 20;

/// At most this many waiting requests on one node (§15.4) —
/// enforced in `node_invitation.dart`, which sees all invitations.
const int kBufferTotal = 100;

/// A request waiting for the user's decision (§12.5), as
/// far as the invitation needs to know it.
///
/// Two classes fulfil this, and the difference is exactly one: the
/// living `ContactRequest` (`first_contact_request.dart`) knows its
/// invitation and can therefore be answered; the [LoadedRequest]
/// comes from memory and does not know it yet. The waiting
/// invitation exchanges the second for the first as soon as it arises
/// ([RequestBuffer.bind]).
///
/// The interface stands here and not in `first_contact_invitation.dart`,
/// so that `invitation.dart` can hold the buffer without knowing
/// first contact — the invitation knows WHO is waiting, not how answering works.
abstract interface class WaitingRequest {
  /// Who is asking — the complete, verified address from the seal.
  Address get who;

  /// Where the request came from; the answer goes there.
  CardAddress get origin;

  /// Name and greeting, if the request carried any.
  Introduction? get introduction;

  /// When it arrived — the order in which displacement happens (§15.4).
  DateTime get at;

  /// The requester's fixed neighbour (proposal M, S391), if named.
  CardAddress? get neighbour;

  /// Its one-time answer code (16 B, proposal M) — under it the
  /// acceptance goes to [neighbour].
  Uint8List? get answerCode;
}

/// A request loaded from memory: the same four values, but
/// still without the invitation that can answer it. It lives only between
/// reading the file and creating the waiting invitation.
class LoadedRequest implements WaitingRequest {
  @override
  final Address who;
  @override
  final CardAddress origin;
  @override
  final Introduction? introduction;
  @override
  final DateTime at;
  @override
  final CardAddress? neighbour;
  @override
  final Uint8List? answerCode;

  LoadedRequest({
    required this.who,
    required this.origin,
    required this.at,
    this.introduction,
    this.neighbour,
    this.answerCode,
  });
}

/// The waiting requests of ONE invitation, oldest first.
///
/// They are a list and not a set: §15.4 displaces "the oldest
/// unanswered", and an order that only arises on reading survives
/// no restart. Therefore the order of this list is the
/// displacement order, and exactly it goes to disk.
class RequestBuffer {
  final List<WaitingRequest> _list = [];

  /// The waiting requests, oldest first.
  List<WaitingRequest> get all => List.unmodifiable(_list);

  int get number => _list.length;

  /// §15.4 point 2: „This invitation is at its buffer limit" — the next
  /// request displaces the oldest.
  bool get atThreshold => _list.length >= kBufferPerInvitation;

  bool leads(WaitingRequest a) => _list.contains(a);

  /// Admits [a]. A renewed request from the SAME peer replaces the
  /// waiting one (and is not a second question); above [kBufferPerInvitation]
  /// the oldest unanswered one falls — §15.4 point 1: displace, never
  /// block. Says whether [a] is a NEW question.
  bool admit(WaitingRequest a) {
    final before = _list.length;
    _list.removeWhere((x) => x.who.sameIdentity(a.who));
    final fresh = _list.length == before;
    _list.add(a);
    while (_list.length > kBufferPerInvitation) {
      _list.removeAt(0);
    }
    return fresh;
  }

  /// Takes [a] out without an answer — the displacement from §15.4 and the
  /// path that a decided request takes.
  bool drop(WaitingRequest a) => _list.remove(a);

  /// Adopts what came from memory — in the order read,
  /// so that the displacement order survives the restart, and with
  /// the same cap: what goes beyond [kBufferPerInvitation] falls
  /// off at the front (the oldest), as in ongoing operation too.
  void adopt(Iterable<WaitingRequest> loaded) {
    _list
      ..clear()
      ..addAll(loaded);
    while (_list.length > kBufferPerInvitation) {
      _list.removeAt(0);
    }
  }

  /// Exchanges every [LoadedRequest] for the living version that knows its
  /// invitation. After that every waiting request is decidable (E-1) —
  /// and the order has stayed the same.
  void bind(WaitingRequest Function(LoadedRequest a) alive) {
    for (var i = 0; i < _list.length; i++) {
      final a = _list[i];
      if (a is LoadedRequest) _list[i] = alive(a);
    }
  }
}
