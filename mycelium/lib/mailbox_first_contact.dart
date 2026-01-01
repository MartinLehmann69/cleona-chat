/// The mailbox side of the first-contact store (proposal E,
/// `memory_first_contact.dart`): what a waiting request carries beyond the
/// memory, and the open joins — written at every change, read at start.
///
/// A separate file for the same reason as `mailbox_invitation.dart`: the line
/// budget of `mailbox.dart`. It gets by with the public side of [Mailbox].
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:mycelium/first_contact.dart' show Join;
import 'package:mycelium/invitation.dart' as inv;
import 'package:mycelium/mailbox.dart';
import 'package:mycelium/mailbox_format_reset.dart';
import 'package:mycelium/mailbox_group_pair.dart' show MailboxGroupPair;
import 'package:mycelium/mailbox_invitation.dart';
import 'package:mycelium/mailbox_start.dart';
import 'package:mycelium/memory.dart';
import 'package:mycelium/memory_enforcer.dart' show legacyDataClear;
import 'package:mycelium/memory_first_contact.dart';
import 'package:mycelium/node_join.dart';

extension MailboxFirstContact on Mailbox {
  FirstContactStore get _store => _stores[this]!;

  /// Opens the store of this identity — in the constructor, before the
  /// invitations are restored. A store that cannot be read is reported and
  /// replaced by an empty one: it holds only what is in transit, and a
  /// damaged one must not keep the identity from starting.
  ///
  /// A store of a FOREIGN version is removed by the enforcer first, like the
  /// memory, and that is reported to the application (W-a,
  /// `mailbox_format_reset.dart`): its open joins are gone. The memory's
  /// reset was noted in [mailboxPrepare]; both reach the mailbox here.
  void firstContactOpen(MailboxDetails a) {
    if (legacyDataClear(
        directory: a.directory,
        fileName: kFileFirstContact,
        runningVersion: kVersionFirstContact,
        key: a.key,
        report: report)) {
      formatResetNote(a, FormatReset.firstContact);
    }
    formatResetAdopt(a);
    try {
      _stores[this] = FirstContactStore.open(a.directory, a.key);
    } on MemoryError catch (e) {
      report?.call('first-contact store not readable — starts empty: $e');
      a.directory.createSync(recursive: true);
      _stores[this] = FirstContactStore.empty(a.directory, a.key);
    }
    _onJoinCompleted[this] = a.onJoinCompleted;
    // The group-pair store (§4.3, B-3 E5 = b) opens at the same moment and
    // for the same reason: `mailbox.dart` has no line left for it.
    groupPairOpen(a);
  }

  /// The living invitation for [g] at start: its waiting requests with their
  /// day keys and marks, and its own sealing keys (R-b) — all from the store.
  /// Without keys (none stored: issued before, or revoked) a request from a
  /// `cleona:2:` line does not open; one after a bundle (1) still does.
  inv.Invitation firstContactInvitation(RememberedInvitation g) {
    final s = _store.invitationKeys[FirstContactStore.codeKey(g.code)];
    return invitationFromRemembered(_extras(g))
      ..kem = s?.kem
      ..box = s?.box;
  }

  RememberedInvitation _extras(RememberedInvitation g) {
    final requests = [
      for (final r in g.requests)
        if (_store.requests[FirstContactStore.requestKey(g.code, r.who)]
            case final x?)
          inv.LoadedRequest(
              who: r.who,
              origin: r.origin,
              at: r.at,
              introduction: r.introduction,
              neighbour: r.neighbour,
              answerCode: r.answerCode,
              dayKeys: x.dayKeys,
              collected: x.collected)
        else
          r,
    ];
    return (
      code: g.code,
      kind: g.kind,
      expiryUnixSeconds: g.expiryUnixSeconds,
      difficulty: g.difficulty,
      atMost: g.atMost,
      accepted: g.accepted,
      revoke: g.revoke,
      inPerson: g.inPerson,
      label: g.label,
      requests: requests,
      cardNeighbour: g.cardNeighbour,
      shownAtMs: g.shownAtMs,
    );
  }

  /// Writes what the waiting requests of THIS identity carry beyond the
  /// memory, and the sealing keys of every invitation whose record still
  /// accepts — with every `invitationsRemember`. A revoked one or one past
  /// expiry + 7 d is not written: its secret leaves the file (R-b).
  void firstContactSave() {
    final s = _store
      ..requests.clear()
      ..invitationKeys.clear();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    for (final e in identity.invitations.all) {
      final k = e.kem, box = e.box;
      if (k != null &&
          box != null &&
          !e.revoke &&
          now <= e.expiryUnixSeconds + inv.kGracePeriodSeconds) {
        s.invitationKeys[FirstContactStore.codeKey(e.code)] =
            (kem: k, box: box);
      }
      for (final r in e.requests.all) {
        if (r.dayKeys.isEmpty) continue;
        s.requests[FirstContactStore.requestKey(e.code, r.who)] =
            (collected: r.collected, dayKeys: r.dayKeys);
      }
    }
    s.save();
  }

  /// [b]'s request is out: remember it until its answer comes. [pkInv] for
  /// an out-of-band join (S405 F-1): with it the request that no post box has
  /// taken yet, so it goes out again after a restart (version 3).
  void joinRemember(Join b, {Uint8List? pkInv}) {
    final g = b.counterpart, w = b.requestWindow;
    if (b.done || b.declined || g == null || w == null) return;
    _store.joins
      ..removeWhere((j) => _equal(j.answerCode, b.answerCode))
      ..add((
        card: b.card,
        counterpart: g,
        answerCode: b.answerCode,
        window: w,
        pkInv: pkInv,
        request: pkInv == null ? null : node.joinPendingRequest(b),
      ));
    _store.save();
  }

  /// [b] is answered (or given up): nothing more to restore.
  void joinForget(Join b) {
    final before = _store.joins.length;
    _store.joins.removeWhere((j) => _equal(j.answerCode, b.answerCode));
    if (_store.joins.length != before) _store.save();
  }

  /// At start: every remembered join waits again for its answer — unless its
  /// card is past expiry + 7 d (the issuer's grace period, §15.3), then it
  /// is dropped. The contact that comes of it is reported upwards
  /// ([MailboxDetails.onJoinCompleted]); nobody waits for a future any more.
  void joinsRestore() {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final before = _store.joins.length;
    _store.joins.removeWhere(
        (j) => now > j.card.expiryUnixSeconds + inv.kGracePeriodSeconds);
    if (_store.joins.length != before) _store.save();
    for (final j in List.of(_store.joins)) {
      final result = Completer<Contact>();
      result.future.then((k) => _onJoinCompleted[this]?.call(k),
          onError: (Object _) {});
      late final Join restored;
      restored = node.joinRestore(j.card, j.counterpart, j.answerCode, j.window,
          forField: identity,
          pkInv: j.pkInv,
          request: j.request,
          onPlaced: () => joinRemember(restored, pkInv: j.pkInv))
        ..onCompletion = (b) => unawaited(joinComplete(b, j.card, result));
      report?.call('join restored — waiting for the answer '
          '(${identifierFrom(j.counterpart).substring(0, 8)})');
    }
  }
}

final Expando<FirstContactStore> _stores = Expando('firstContactStore');
final Expando<void Function(Contact)> _onJoinCompleted =
    Expando('onJoinCompleted');

bool _equal(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
