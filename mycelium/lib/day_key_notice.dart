/// The day-key notice to a contact or a group pair counts as sent only with
/// its receipt or its placing (V4.2 §8.2, §9.2, §9.3; S398 N-1a, S408-RESEND
/// W-2b).
///
/// §8.2: the day keys go to "each contact and each group pair … sealed as
/// an ordinary message — at an edge …, when the last such message to that
/// contact or pair is older than 14 days"; §9.3: "At the edges of §8.2 the
/// node sends again, under the same identifier, what is neither acknowledged
/// nor placed". "The last such message" is the last one that ARRIVED or lies
/// in a post box — one that was lost does not count.
///
/// Until S408 a CONTACT's notice was noted as sent when it LEFT
/// (`dayKeySent` written at sending, `mailbox_pair.dart`): a renewal lost on
/// the way went at no edge for 14 more days, and the contact's day keys ran
/// 31 − 14 − 14 = 3 days past the next chance (S407-OLAPPW §4.1, W-2b). The
/// group pair's notice already counted with its receipt only (S398 N-1a);
/// both now take this ONE way, and a placing counts like a receipt (§9.3
/// "neither acknowledged nor placed").
///
/// ── WHAT IS HELD WHERE ─────────────────────────────────────────────────
///
/// The notices under way are held in memory only: after a restart the peer
/// is due again and the start edge sends anew — one notice per restart and
/// peer whose last notice was not counted. What is counted is the moment in
/// the peer's record (`Contact.dayKeySent`, `GroupPair.dayKeySent`), on disk.
///
/// ONE notice per peer is under way (§9.3 "under the same identifier", S408
/// F-3): at an edge it goes AGAIN under its identifier and with its content,
/// unless its placing still runs; a new one is built only when its content is
/// [kDayKeyInterval] old. Until S408 F-3 every edge built a new notice with a
/// new identifier, and for an absent peer they piled up without end. Its
/// receipt or placing counts. An Emergency Key Rotation (§4.5.4) forgets the
/// notice under way ([dayKeyNoticesForget]): it carries keys of the replaced
/// signing key, and a late receipt of it must not count for the one that
/// follows.
library;

import 'dart:typed_data';

import 'package:mycelium/card_address.dart' show CardAddress;
import 'package:mycelium/envelope.dart' show Address;
import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/mailbox.dart';
import 'package:mycelium/mailbox_group_pair.dart' show MailboxGroupPair;
import 'package:mycelium/mailbox_pair.dart' show kDayKeyInterval;
import 'package:mycelium/message.dart' show Outbound;

extension DayKeyNotice on Mailbox {
  /// Sends the day-key notice [content] to [to] — a contact (with its
  /// [destination], if one is known) or a group pair (none). With a notice to
  /// [to] still under way: that one again, under its identifier (§9.3) —
  /// nothing while its placing runs, a new one once it is [kDayKeyInterval]
  /// old.
  void dayKeyNoticeSend(Address to, Uint8List content, CardAddress? destination) {
    final id = identifierFrom(to);
    final now = DateTime.now();
    final open = _open(this);
    final prior = open.entries.where((e) => e.value.peer == id).firstOrNull;
    var body = content;
    var built = now;
    Uint8List? under;
    if (prior != null) {
      if (now.difference(prior.value.built) < kDayKeyInterval) {
        final running = node.shipmentOf(prior.key);
        if (running != null && running.placed == null) {
          // Its placing runs: neither acknowledged nor placed yet. The edge
          // is noted and answered when the placing ends unplaced — the way
          // of the history's messages (`mailbox_outbound.dart`).
          open[prior.key] = (
            peer: id,
            content: prior.value.content,
            built: prior.value.built,
            identifier: prior.value.identifier,
            to: to,
            destination: destination,
            edgePassed: true
          );
          return;
        }
        (body, built, under) = (prior.value.content, prior.value.built,
            prior.value.identifier);
      } else {
        open.remove(prior.key); // stale content: a new notice replaces it
      }
      node.shipmentEnd(prior.key);
    }
    final out = node.send(body, to, destination,
        forField: identity, kind: kinds.kDayKey, under: under);
    final hex = _hex(out.identifier);
    open[hex] = (
      peer: id,
      content: body,
      built: built,
      identifier: out.identifier,
      to: to,
      destination: destination,
      edgePassed: false
    );
    node.shipmentOf(hex)?.onPlacingEnd = (placed) {
      if (placed) return _counted(hex, DateTime.now(), 'placed');
      final n = open[hex];
      // Unplaced, and an edge passed meanwhile: it goes again — once.
      if (n != null && n.edgePassed) dayKeyNoticeSend(n.to, n.content, n.destination);
    };
    report?.call('day keys to ${_kind(id)} ${id.substring(0, 8)} '
        '${under == null ? 'sent' : 'sent again'} (${hex.substring(0, 6)}) '
        '— counted with its receipt or placing');
  }

  /// A receipt of this identity (`MailboxInbound.receiptArrived`): if it is
  /// one of a day-key notice, that notice counts as sent now.
  void dayKeyNoticeAcked(Outbound out) => _counted(
      _hex(out.identifier), out.acknowledgedAt ?? DateTime.now(), 'receipted');

  void _counted(String hex, DateTime at, String how) {
    final id = _open(this).remove(hex)?.peer;
    if (id == null) return;
    _end(id);
    final k = contactOrNull(id);
    if (k != null) {
      contactRemember(k.address, dayKeySent: at);
    } else if (!groupPairDayKeysCounted(id, at)) {
      return;
    }
    report?.call('day keys to ${_kind(id)} ${id.substring(0, 8)} $how');
  }

  /// Ends every notice to [id] still under way and forgets it.
  void _end(String id) {
    _open(this).removeWhere((hex, n) {
      if (n.peer != id) return false;
      node.shipmentEnd(hex);
      return true;
    });
  }

  /// After an Emergency Key Rotation: no notice under way counts any more.
  void dayKeyNoticesForget() {
    for (final hex in _open(this).keys) {
      node.shipmentEnd(hex);
    }
    _open(this).clear();
  }

  String _kind(String id) =>
      contactOrNull(id) != null ? 'contact' : 'group pair';
}

/// A day-key notice not counted yet: the peer (identifier, hex) it went to,
/// what it carries, when that was built, its identifier, where it goes, and
/// whether an edge passed while its placing ran.
typedef _Notice = ({
  String peer,
  Uint8List content,
  DateTime built,
  Uint8List identifier,
  Address to,
  CardAddress? destination,
  bool edgePassed
});

/// Per mailbox: identifier (hex) of the notice under way -> the notice; at
/// most one per peer.
final Expando<Map<String, _Notice>> _notices = Expando('dayKeyNoticeOpen');
Map<String, _Notice> _open(Mailbox m) => _notices[m] ??= {};

String _hex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
